enum SonosAPIError: Error, Comparable {
    case failedLoading
    case failedParsing
    case deviceNotFound
    case queueEmpty
    case requestBuild
}
