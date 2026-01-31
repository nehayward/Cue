import SonosKit
import SwiftUI

final class QueueManager {
    static let shared = QueueManager()
    
    private(set) var isProcessing = false
    private var queue: AsyncStream<QueueItem>?
    private var continuation: AsyncStream<QueueItem>.Continuation?
    
    private var alertService: AlertService
    private var sonosService: SonosService
    private var playHistoryService: PlayHistoryService
    
    var lastQueuedItem: QueueItem?
    
    init(alertService: AlertService = .shared,
         sonosService: SonosService = .shared,
         playHistoryService: PlayHistoryService = .shared) {
        self.alertService = alertService
        self.sonosService = sonosService
        self.playHistoryService = playHistoryService
        
        // Initialize the AsyncStream
        let (stream, continuation) = AsyncStream.makeStream(of: QueueItem.self)
        self.queue = stream
        self.continuation = continuation
        
        // Start processing the queue
        Task { await processQueue() }
    }
    
    func addToQueue(item: QueueItem) {
        continuation?.yield(item)
        Task { @MainActor in
            if !item.showBanner {
                self.lastQueuedItem = item
            }
        }
    }
    
    func add(items: [QueueItem]) {
        for item in items {
            continuation?.yield(item)
            Task { @MainActor in
                if !item.showBanner {
                    self.lastQueuedItem = item
                }
            }
        }
    }
    
    @MainActor
    private func processQueue() async {
        guard let queue = queue else { return }
        
        for await item in queue {
            isProcessing = true
            do {
                try await playSong(item)
            } catch {
                handleError(for: item.playableContent, error: error)
            }
            isProcessing = false
        }
    }
    
    
    private func playSong(_ queueItem: QueueItem) async throws {
        HapticManager.shared.fireHaptic(.buttonPress)
        
        let playableContent = queueItem.playableContent
        let group = queueItem.group
        
        if queueItem.showBanner {
            alertService.showAlertContent(with: playableContent, subtitle: LocalizedStringKey(queueItem.title))
        }
        
        try await sonosService.queue(playable: playableContent, group: group, position: queueItem.position, index: queueItem.index)
        
        if [.now, .replace].contains(queueItem.position) {
            await sonosService.play(ip: group.coordinatorRoom.ip)
        }
        
        Task { @MainActor in
            playHistoryService.history.remove(playableContent)
            playHistoryService.history.insert(playableContent, at: 0)
        }
    }
    
    @MainActor
    private func handleError(for item: PlayableContent, error: Error) {
        guard let error = error as? SonosServiceError else {
            alertService.showAlert(with: "Please authorize \(item.content.service.title) in Sonos", imageName: "exclamationmark.triangle.fill")
            return
        }
        
        switch error {
        case .timeout:
            alertService.showAlert(with: "Timed out waiting for Sonos to respond", imageName: "exclamationmark.triangle.fill")
        case .serviceUnavailable:
            Task {
                let services = await sonosService.services()
                if services.filter({ $0.type.rawValue.lowercased().contains(item.content.service.sonosRawValue )}).count > 1 {
                    let service = item.content.service.title
                    alertService.showAlert(with: "Multiple \(service) accounts in Sonos. Set your preferred one in Clic Services.", imageName: "exclamationmark.triangle.fill") {
                        Router.main.presentedSheet = .settings(destination: .servicePreferenceScreen)
                    }
                } else if !services.filter({ $0.type.rawValue.lowercased().contains(item.content.service.sonosRawValue )}).isEmpty {
                    alertService.showAlert(with: "Failed to play \(item.title), contact support", imageName: "exclamationmark.triangle.fill")
                } else {
                    alertService.showAlert(with: "Please authorize service \(item.content.service.title) in Sonos, Tap to open Sonos", imageName: "exclamationmark.triangle.fill") {
                        UIApplication.shared.open(URL(string: "sonos://")!)
                    }
                }
            }
        default:
            alertService.showAlert(with: "Failed to queue  \(item.content.service.title), ensure service is authorized", imageName: "exclamationmark.triangle.fill")
        }
    }
}

struct QueueItem {
    let playableContent: PlayableContent
    let group: GroupRoom
    let position: QueuePosition
    var index: Int? = nil
    var total: Int = 1
    var title: String = ""
    var showBanner: Bool = true
}
//
//final class QueueManager {
//    static var shared = QueueManager()
//    private var alertService: AlertService
//
//    init(alertService: AlertService = .shared) {
//        self.alertService = alertService
//    }
//
//    private func play(_ position: QueuePosition = .now) {
//
//        //    func play(_ item: PlayableContent) {
//        //        Task { @MainActor in
//        //            let queueSong: ((GroupRoom) async throws -> Void) = { group in
//        //                HapticManager.shared.fireHaptic(.buttonPress)
//        //                do {
//        //                    if let parent {
//        //                        await sonosService.setPlayMode(group.ip, mode: [.normal])
//        //                        var subtitle: LocalizedStringKey
////
//        //                        if let totalSongs = parent.metadata?.totalSongs {
//        //                            subtitle = "Added ^[\(totalSongs) song](inflect: true), playing \(item.title) now."
//        //                        } else {
//        //                            subtitle = "Playing \(item.title) now."
//        //                        }
////
//        //                        alertService.showAlertContent(with: parent, subtitle: subtitle)
////
//        //                        if [.playlist, .libraryPlaylist].contains(parent.content.type) {
//        //                            try await sonosService.replaceQueue(playable: parent, group: group, index: index ?? 0)
//        //                        } else {
//        //                            try await sonosService.queue(playable: parent, group: group, index: index)
//        //                        }
////
//        //                        await sonosService.play(ip: group.coordinatorRoom.ip)
//        //                        playHistoryService.history.remove(parent)
//        //                        playHistoryService.history.insert(parent, at: 0)
//        //                        return
//        //                    }
////
//        //                    alertService.showAlertContent(with: item, subtitle: "Added to Queue")
//        //                    try await sonosService.queue(playable: item, group: group, position: position, replaceQueue: replaceQueue)
//        //                    await sonosService.play(ip: group.coordinatorRoom.ip)
//        //                    playHistoryService.history.remove(item)
//        //                    playHistoryService.history.insert(item, at: 0)
//        //                } catch {
//        //                    alertService.showAlert(with: "Please authorize \(item.content.service.title) in Sonos", imageName: "exclamationmark.triangle.fill")
//        //                }
//        //            }
//        //        }
//        //    }
//    }
//}
