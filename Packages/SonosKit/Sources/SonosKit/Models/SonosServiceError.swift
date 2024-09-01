
enum SonosServiceError: Error {
    case noWifi
    case sonosSystemNotFound
    case permissionDenied
    case cancelled
    case parseError(String)
    case timeout
    case serviceUnavailable
}
