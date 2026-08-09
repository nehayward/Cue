enum SonosAPIError: Error, Comparable {
    case failedLoading
    case failedParsing
    case deviceNotFound
    case queueEmpty
    case requestBuild
    /// The device answered, but doesn't offer the thing we asked for (e.g. an EQ
    /// type it doesn't implement). Distinct from `failedLoading`, which means we
    /// never got an answer — a dropped request must not read as "unsupported".
    case unsupported
}
