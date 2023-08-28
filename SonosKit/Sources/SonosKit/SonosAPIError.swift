extension SonosAPI {
    enum SonosAPIError: Error {
        case failedLoading
        case failedParsing
        case deviceNotFound
        case queueEmpty
    }
}
