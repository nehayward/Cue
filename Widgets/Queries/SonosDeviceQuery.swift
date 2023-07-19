import AppIntents
import SonosKit

struct SonosDeviceQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [SonosDeviceEntity.ID]) async throws -> [SonosDeviceEntity] {
        return await SonosService().getGroups().flatMap(\.rooms).map { room in
            return SonosDeviceEntity(id: room.id, name: room.name, ip: room.ip, volume: room.volume)
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [SonosDeviceEntity] {
        return await SonosService().getGroups().flatMap(\.rooms).map { room in
            return SonosDeviceEntity(id: room.id, name: room.name, ip: room.ip, volume: room.volume)
        }
    }
//
//    func defaultResult() async -> SonosDeviceEntity? {
//        try? await suggestedEntities().first
//    }
}
