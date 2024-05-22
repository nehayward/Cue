
public enum Features: String {
    case tidalSupport

    public var key: String {
        "\(Prefix.id).\(self.rawValue)"
    }
}
