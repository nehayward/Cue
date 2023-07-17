import AppIntents
import SonosKit

struct SonosDeviceQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [SonosSpeakerEntity.ID]) async throws -> [SonosSpeakerEntity] {
        return await SonosService().getGroups().flatMap(\.rooms).map { room in
            return SonosSpeakerEntity(id: room.id, name: room.name, ip: room.ip, volume: room.volume)
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [SonosSpeakerEntity] {
        return await SonosService().getGroups().flatMap(\.rooms).map { room in
            return SonosSpeakerEntity(id: room.id, name: room.name, ip: room.ip, volume: room.volume)
        }
    }

    func defaultResult() async -> SonosSpeakerEntity? {
        try? await suggestedEntities().first
    }
}
