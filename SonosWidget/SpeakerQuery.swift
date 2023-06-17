import AppIntents
import SonosKit

struct SpeakerQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [SonosSpeakerEntity.ID]) async throws -> [SonosSpeakerEntity] {
        return await SonosService().getRooms().map { room in
            return SonosSpeakerEntity(id: room.UUID, name: room.zoneName, ip: room.ip, volume: 0)
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [SonosSpeakerEntity] {
        return await SonosService().getRooms().map { room in
            return SonosSpeakerEntity(id: room.UUID, name: room.zoneName, ip: room.ip, volume: 0)
        }
    }

    func defaultResult() async -> SonosSpeakerEntity? {
        try? await suggestedEntities().first
    }
}
