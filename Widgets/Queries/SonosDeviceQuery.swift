import AppIntents
import SonosKit
import Defaults

struct SonosDeviceQuery: EntityQuery {
    private static var sonosService = SonosService.shared

    @MainActor
    func entities(for identifiers: [SonosDeviceEntity.ID]) async throws -> [SonosDeviceEntity] {
        // TODO: Need this flag so network permission isn't triggered
//        guard let storage = GroupStorageKeys.storage, storage.bool(forKey: GroupStorageKeys.hasOnboarded) else {
//            return []
//        }
        return try await Self.sonosService.getGroups(useCache: true).flatMap(\.rooms).map { room in
            return SonosDeviceEntity(id: room.id, ip: room.ip, name: room.name)
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [SonosDeviceEntity] {
        // TODO: Need this flag so network permission isn't triggered

//        guard let storage = GroupStorageKeys.storage, storage.bool(forKey: GroupStorageKeys.hasOnboarded) else {
//            return []
//        }
        
        return try await Self.sonosService.getGroups(useCache: true).flatMap(\.rooms).map { room in
            return SonosDeviceEntity(id: room.id, ip: room.ip, name: room.name)
        }
    }
}
