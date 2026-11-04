import AppKit
import CoreServices

/// Reads and deletes the Music app's playlists by Apple event. Raw events rather
/// than AppleScript: `NSAppleScript` runs only on the main thread, and these wait
/// on Music, the first time on the listener at the Automation prompt.
///
/// Music's sandbox check walks a request's specifier against its dictionary, so
/// every request names the path the dictionary declares: a `user playlist` is an
/// element of a `source`, not of the application, and `every user playlist` on
/// its own is refused with -10004.
final class MusicLibraryScripter: NSObject, MusicLibraryScriptable, @unchecked Sendable {
    private static let bundleID = "com.apple.Music"
    private static let noSuchObject = -1728

    /// The calls block until Music answers, so they stay off the cooperative
    /// pool, one at a time.
    private let queue = DispatchQueue(label: "dance.cue.musicLibraryScripter")

    private let target = NSAppleEventDescriptor(bundleIdentifier: MusicLibraryScripter.bundleID)

    // MARK: - MusicLibraryScriptable

    func playlists() async throws -> [[String: String]] {
        try await withConnection { [self] in
            // `properties` in one event, so the rows are of one moment.
            let rows = try get(property("pALL", of: every("cPly", in: try librarySource())))
            return items(of: rows).map { row in
                [
                    "name": row.forKeyword(code("pnam"))?.stringValue ?? "",
                    "persistentID": row.forKeyword(code("pPIS"))?.stringValue ?? "",
                    "kind": kind(of: row),
                ]
            }
        }
    }

    func trackCount(ofPlaylist persistentID: String) async throws -> Int {
        try await withConnection { [self] in
            let playlist = try userPlaylist(persistentID: persistentID)
            let count = try send("cnte", direct: playlist, parameters: ["kocl": NSAppleEventDescriptor(typeCode: code("cTrk"))])
            return Int(count.int32Value)
        }
    }

    func deletePlaylist(persistentID: String, named name: String) async throws {
        try await withConnection { [self] in
            let playlist = try userPlaylist(persistentID: persistentID)
            // What this specifier names right now is what's about to go.
            guard try get(property("pnam", of: playlist)).stringValue == name,
                  try get(property("pPIS", of: playlist)).stringValue == persistentID else {
                throw error(Self.noSuchObject)
            }

            _ = try send("delo", direct: playlist, timeout: 60)

            do {
                _ = try get(property("pPIS", of: playlist))
            } catch let error as NSError where error.code == Self.noSuchObject {
                return
            }
            throw error(Int(errAEEventFailed))
        }
    }

    // MARK: - Reaching Music

    /// Opens Music in the background if it's closed: it's what answers. It's
    /// left open, since iCloud hears of a change from it after the event returns.
    private func openMusicIfNeeded() async throws {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty else { return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else {
            throw error(Int(procNotFound))
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    /// Runs `work` on the queue once Music is open, this app may ask it and it
    /// answers.
    private func withConnection<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await openMusicIfNeeded()
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                continuation.resume(with: Result {
                    try waitForMusic()
                    return try work()
                })
            }
        }
    }

    /// Asks for permission (a prompt the first time), then for Music's version,
    /// for up to 20 s while a Music just opened gets going.
    private func waitForMusic() throws {
        let deadline = Date.now.addingTimeInterval(20)
        var status = OSStatus(procNotFound)
        while Date.now < deadline {
            status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true)
            if status == noErr {
                do {
                    _ = try send("getd", direct: property("vers", of: .null()), timeout: 5)
                    return
                } catch let error as NSError where Self.isStillOpening(error.code) {
                    status = OSStatus(error.code)
                }
            } else if status != OSStatus(procNotFound) {
                throw error(Int(status))
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        throw error(Int(status))
    }

    private static func isStillOpening(_ code: Int) -> Bool {
        code == Int(procNotFound) || code == Int(connectionInvalid) || code == Int(errAETimeout)
    }

    // MARK: - Specifiers

    /// The library's source, by its kind: the others are the iTunes Store and
    /// any CD or shared library.
    private func librarySource() throws -> NSAppleEventDescriptor {
        let kinds = items(of: try get(property("pKnd", of: every("cSrc", in: .null()))))
        guard let index = kinds.firstIndex(where: { $0.enumCodeValue == code("kLib") }) else {
            throw error(Self.noSuchObject)
        }
        return specifier(class: "cSrc", in: .null(), form: "indx", data: NSAppleEventDescriptor(int32: Int32(index + 1)))
    }

    /// `user playlist id … of <library>`, found by persistent ID, or a
    /// no-such-object error. Asked by `id` from here on: `get` follows a `whose`
    /// specifier, but `count` through one answers 0 whatever it names, so no
    /// other command is trusted with one.
    private func userPlaylist(persistentID: String) throws -> NSAppleEventDescriptor {
        let library = try librarySource()
        let examined = NSAppleEventDescriptor(descriptorType: code("exmn"), data: nil)!
        let comparison = NSAppleEventDescriptor.record()
        comparison.setDescriptor(NSAppleEventDescriptor(enumCode: code("=   ")), forKeyword: code("relo"))
        comparison.setDescriptor(property("pPIS", of: examined), forKeyword: code("obj1"))
        comparison.setDescriptor(NSAppleEventDescriptor(string: persistentID), forKeyword: code("obj2"))
        let matching = specifier(class: "cUsP", in: library, form: "test", data: comparison.coerce(toDescriptorType: code("cmpd"))!)
        let ids = items(of: try get(property("ID  ", of: matching)))
        guard ids.count == 1, let id = ids.first?.int32Value else { throw error(Self.noSuchObject) }
        return specifier(class: "cUsP", in: library, form: "ID  ", data: NSAppleEventDescriptor(int32: id))
    }

    private func every(_ elementClass: String, in container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        var all = code("all ")
        let data = NSAppleEventDescriptor(descriptorType: code("abso"), bytes: &all, length: MemoryLayout<UInt32>.size)!
        return specifier(class: elementClass, in: container, form: "indx", data: data)
    }

    private func property(_ name: String, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        specifier(class: "prop", in: container, form: "prop", data: NSAppleEventDescriptor(typeCode: code(name)))
    }

    private func specifier(
        class elementClass: String,
        in container: NSAppleEventDescriptor,
        form: String,
        data: NSAppleEventDescriptor
    ) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: code(elementClass)), forKeyword: code("want"))
        record.setDescriptor(container, forKeyword: code("from"))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: code(form)), forKeyword: code("form"))
        record.setDescriptor(data, forKeyword: code("seld"))
        return record.coerce(toDescriptorType: code("obj "))!
    }

    // MARK: - Events

    private func get(_ specifier: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        try send("getd", direct: specifier)
    }

    private func send(
        _ eventID: String,
        direct: NSAppleEventDescriptor,
        parameters: [String: NSAppleEventDescriptor] = [:],
        timeout: TimeInterval = 30
    ) throws -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: code("core"),
            eventID: code(eventID),
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setParam(direct, forKeyword: code("----"))
        for (keyword, value) in parameters {
            event.setParam(value, forKeyword: code(keyword))
        }
        let reply = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: timeout)
        if let number = reply.paramDescriptor(forKeyword: code("errn"))?.int32Value, number != 0 {
            throw error(Int(number))
        }
        return reply.paramDescriptor(forKeyword: code("----")) ?? .null()
    }

    /// The rows of a list reply. `numberOfItems` also counts a record's keys,
    /// so a reply of one thing that isn't a list counts as that one thing.
    private func items(of list: NSAppleEventDescriptor) -> [NSAppleEventDescriptor] {
        guard list.descriptorType == code("list") else {
            return list.descriptorType == code("null") ? [] : [list]
        }
        guard list.numberOfItems > 0 else { return [] }
        return (1 ... list.numberOfItems).compactMap { list.atIndex($0) }
    }

    /// A `MusicPlaylist.Kind`'s raw value, from a playlist's properties.
    private func kind(of row: NSAppleEventDescriptor) -> String {
        switch row.forKeyword(code("pcls"))?.typeCodeValue {
        case code("cUsP"):
            if row.forKeyword(code("pSmt"))?.booleanValue != false { return "smart" }
            if row.forKeyword(code("pGns"))?.booleanValue != false { return "genius" }
            if row.forKeyword(code("pSpK"))?.enumCodeValue != code("kNon") { return "special" }
            return "plain"
        case code("cFoP"):
            return "folder"
        case code("cSuP"):
            return "subscription"
        default:
            return "other"
        }
    }

    private func code(_ fourCharacters: String) -> UInt32 {
        fourCharacters.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private func error(_ code: Int) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: code)
    }
}
