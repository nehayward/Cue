public struct TheaterSettings: Codable, Hashable, Equatable {
    public var isSet: Bool

    public var nightMode: Bool = false
    public var dialogLevel: Bool = false
    /// Arc Ultra only: nil means unsupported, non-nil means Arc Ultra dialog toggle
    public var speechEnhanceEnabled: Bool? = nil
    /// Arc Ultra only: dialog intensity level (1=Low, 2=Medium, 3=High, 4=Max)
    public var dialogLevelValue: Int = 1
    public var audioInputFormat: AudioInputFormat = .noInputConnected
    /// TV Dialog Sync (lip sync) delay, 0–5. Soundbars only.
    public var audioDelay: Double = .zero

    public var surroundLevel: Double = .zero
    public var musicSurroundLevel: Double = .zero
    public var isSurroundEnable: Bool = false
    public var surroundMode: Double = .zero
    public var heightChannel: Double = .zero

    public var subGain: Double = .zero
    public var isSubEnabled: Bool = false
}
