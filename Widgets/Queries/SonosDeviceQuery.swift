import AppIntents
import SonosKit
import Defaults

struct SonosDeviceQuery: EntityQuery {
    private static var sonosService = SonosService.shared

    @MainActor
    func entities(for identifiers: [SonosDeviceEntity.ID]) async throws -> [SonosDeviceEntity] {
        return try await Self.sonosService.getGroups(useCache: true).flatMap(\.rooms).map { room in
            return SonosDeviceEntity(id: room.id, ip: room.ip, name: room.name, isArcUltra: room.isArcUltraIfKnown)
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [SonosDeviceEntity] {
        return try await Self.sonosService.getGroups(useCache: true).flatMap(\.rooms).map { room in
            return SonosDeviceEntity(id: room.id, ip: room.ip, name: room.name, isArcUltra: room.isArcUltraIfKnown)
        }
    }
}
