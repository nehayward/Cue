public struct TheaterSettings: Codable, Hashable, Equatable {
    public var isSet: Bool

    public var nightMode: Bool = false
    public var dialogLevel: Bool = false
    public var audioInputFormat: AudioInputFormat = .noInputConnected

    public var surroundLevel: Double = .zero
    public var musicSurroundLevel: Double = .zero
    public var isSurroundEnable: Bool = false
    public var surroundMode: Double = .zero
    public var heightChannel: Double = .zero

    public var subGain: Double = .zero
    public var isSubEnabled: Bool = false
}
