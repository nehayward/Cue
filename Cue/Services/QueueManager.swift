import MusicSearchKit
import SonosKit
import SwiftUI

@Observable
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
        add(items: [item])
    }

    func add(items: [QueueItem]) {
        items.forEach { continuation?.yield($0) }
        if let last = items.last(where: { !$0.showBanner }) {
            Task { @MainActor in self.lastQueuedItem = last }
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
                await handleError(for: item.playableContent, error: error)
            }
            isProcessing = false
        }
    }
    
    
    @MainActor
    private func playSong(_ queueItem: QueueItem) async throws {
        HapticManager.shared.fireHaptic(.buttonPress)

        let playableContent = queueItem.playableContent
        let group = queueItem.group

        if queueItem.showBanner {
            alertService.showAlertContent(with: playableContent, subtitle: LocalizedStringKey(queueItem.title))
        }

        // Long lists can take seconds to queue. If Sonos hasn't accepted the
        // content after 500ms, switch the banner into a loading state with a
        // spinner so the tap doesn't feel dropped.
        let loadingBanner = Task { @MainActor [alertService] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            alertService.showLoadingContent(with: playableContent)
        }
        defer { loadingBanner.cancel() }

        try await sonosService.queue(playable: playableContent, group: group, position: queueItem.position, index: queueItem.index)

        loadingBanner.cancel()
        if alertService.alert.isLoading {
            // The spinner took over the banner — replace it with the normal
            // confirmation now that the content is actually queued.
            alertService.showAlertContent(with: playableContent, subtitle: LocalizedStringKey(queueItem.title.isEmpty ? "Playing" : queueItem.title))
        }

        if [.now, .replace].contains(queueItem.position) {
            await sonosService.play(ip: group.coordinatorRoom.ip)
        }

        withAnimation {
            playHistoryService.history.remove(playableContent)
            playHistoryService.history.insert(playableContent, at: 0)
        }
    }
    
    @MainActor
    private func handleError(for item: PlayableContent, error: Error) async {
        guard let error = error as? SonosServiceError else {
            alertService.showAlert(with: "Please authorize \(item.content.service.title) in Sonos", imageName: "exclamationmark.triangle.fill")
            return
        }
        
        switch error {
        case .timeout:
            alertService.showAlert(with: "Timed out waiting for Sonos to respond", imageName: "exclamationmark.triangle.fill")
        case .serviceUnavailable:
            let services = await sonosService.services()
            if services.filter({ $0.type.rawValue.lowercased().contains(item.content.service.sonosRawValue) }).count > 1 {
                let service = item.content.service.title
                alertService.showAlert(with: "Multiple \(service) accounts in Sonos. Set your preferred one in Cue Services.", imageName: "exclamationmark.triangle.fill") {
                    Router.main.presentedSheet = .settings(destination: .servicePreferenceScreen)
                }
            } else if !services.filter({ $0.type.rawValue.lowercased().contains(item.content.service.sonosRawValue) }).isEmpty {
                alertService.showAlert(with: "Failed to play \(item.title), contact support", imageName: "exclamationmark.triangle.fill")
            } else {
                alertService.showAlert(with: "Please authorize service \(item.content.service.title) in Sonos, Tap to open Sonos", imageName: "exclamationmark.triangle.fill") {
                    UIApplication.shared.open(URL(string: "sonos://")!)
                }
            }
        case .cantPlayContent(let upnpCode):
            let code = upnpCode.map { " (Sonos error \($0))" } ?? ""
            let service = item.content.service
            if service.queuesContainersAsTracks {
                // Direct-HTTP services have no Sonos-side account to
                // authorize — either the server returned no tracks or the
                // speaker rejected the stream. Name the code so the cause is
                // reportable, and open the server settings on tap.
                alertService.showAlert(with: "Failed to queue from your \(service.title) server\(code). Check that your speakers can reach the server address.", imageName: "exclamationmark.triangle.fill") {
                    if let sheet = MediaSearchService(rawValue: service.sonosRawValue)?.managementSheet {
                        Router.main.presentedSheet = sheet
                    }
                }
            } else {
                alertService.showAlert(with: "Failed to queue  \(service.title)\(code), ensure service is authorized", imageName: "exclamationmark.triangle.fill")
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
