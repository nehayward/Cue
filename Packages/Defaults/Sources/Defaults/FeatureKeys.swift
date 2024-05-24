
public enum Features: String {
    case tidalSupport
    case nowPlaying

    public var key: String {
        "\(Prefix.id).\(self.rawValue)"
    }
}
