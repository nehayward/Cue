import AppIntents
import SonosKit

struct SonosDeviceQuery: EntityQuery {
    private static var sonosService = SonosService()

    @MainActor
    func entities(for identifiers: [SonosDeviceEntity.ID]) async throws -> [SonosDeviceEntity] {
        return try await Self.sonosService.getGroups(useCache: true).flatMap(\.rooms).map { room in
            return SonosDeviceEntity(id: room.id, ip: room.ip, name: room.name, volume: room.volume)
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [SonosDeviceEntity] {
        return try await Self.sonosService.getGroups(useCache: true).flatMap(\.rooms).map { room in
            return SonosDeviceEntity(id: room.id, ip: room.ip, name: room.name, volume: room.volume)
        }
    }
//
//    func defaultResult() async -> SonosDeviceEntity? {
//        try? await suggestedEntities().first
//    }
}
