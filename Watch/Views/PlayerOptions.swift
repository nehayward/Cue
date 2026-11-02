import SwiftUI
import WatchSync

/// A book's speed, as on the iPhone, in a sheet of its own.
struct SpeedPicker: View {
    let current: Double
    var choices: [Double] = WatchBookStore.rateChoices
    let choose: (Double) -> Void

    var body: some View {
        NavigationStack {
            SpeedList(current: current, choices: choices, choose: choose)
        }
    }
}

/// The speeds to pick from, the one playing ticked.
struct SpeedList: View {
    let current: Double
    let choices: [Double]
    let choose: (Double) -> Void

    var body: some View {
        List {
            ForEach(choices, id: \.self) { rate in
                Button {
                    choose(rate)
                } label: {
                    CheckedRow(title: WatchBookFormat.rate(rate), isOn: rate == current)
                }
            }
        }
        .navigationTitle("Speed")
    }
}

/// The sleep timer's choices, in a sheet of its own.
struct SleepTimerPicker: View {
    let endTitle: String
    let isOff: Bool
    let isEnd: Bool
    let choose: (WatchPhoneSleep) -> Void

    var body: some View {
        NavigationStack {
            SleepTimerList(endTitle: endTitle, isOff: isOff, isEnd: isEnd, choose: choose)
        }
    }
}

/// The sleep timer's choices: off, the end of the chapter (or song), or a
/// while.
struct SleepTimerList: View {
    /// "End of Chapter", or "End of Song".
    let endTitle: String
    let isOff: Bool
    let isEnd: Bool
    let choose: (WatchPhoneSleep) -> Void

    var body: some View {
        List {
            row("Off", isOn: isOff) { choose(.off) }
            row(endTitle, isOn: isEnd) { choose(.end) }
            ForEach(WatchPlayer.sleepChoices, id: \.self) { minutes in
                row("\(minutes) min", isOn: false) { choose(.minutes(minutes)) }
            }
        }
        .navigationTitle("Sleep Timer")
    }

    private func row(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CheckedRow(title: title, isOn: isOn)
        }
    }
}

/// A choice in a list, ticked when it's the one in force.
private struct CheckedRow: View {
    let title: String
    let isOn: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 0)
            if isOn {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
    }
}

/// How long the sleep timer has left, counting down, the end it waits for,
/// or Off.
struct SleepTimerValue: View {
    let sleepsAt: Date?
    /// The end it waits for ("End of Chapter"), when that's the timer.
    let end: String?

    var body: some View {
        if let end {
            Text(end)
        } else if let sleepsAt, sleepsAt > .now {
            Text(sleepsAt, style: .timer)
                .monospacedDigit()
        } else {
            Text("Off")
        }
    }
}

extension SleepTimerValue {
    /// The watch's own timer.
    init(timer: WatchPlayer.SleepTimer?, endTitle: String) {
        switch timer {
        case let .at(date):
            self.init(sleepsAt: date, end: nil)
        case .endOfChapter:
            self.init(sleepsAt: nil, end: endTitle)
        case nil:
            self.init(sleepsAt: nil, end: nil)
        }
    }
}

extension WatchPlayer.SleepTimer {
    /// The watch's own timer for a choice: nil for Off.
    init?(_ sleep: WatchPhoneSleep) {
        switch sleep {
        case .off:
            return nil
        case .end:
            self = .endOfChapter
        case let .minutes(minutes):
            self = .at(.now.addingTimeInterval(TimeInterval(minutes * 60)))
        }
    }
}

/// The sleep timer and a book's speed, from the player's bottom left:
/// each a row showing what's set, opening its choices.
struct PlayerOptionsSheet: View {
    /// "End of Chapter", or "End of Song".
    let endTitle: String
    let sleepsAt: Date?
    let sleepsAtEnd: Bool
    /// The speed and its choices; nil where there's none to set (music, a
    /// book on a speaker).
    let speed: (current: Double, choices: [Double])?
    let chooseSleep: (WatchPhoneSleep) -> Void
    let chooseSpeed: (Double) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    SleepTimerList(
                        endTitle: endTitle,
                        isOff: !sleepsAtEnd && !(sleepsAt.map { $0 > .now } ?? false),
                        isEnd: sleepsAtEnd
                    ) { sleep in
                        chooseSleep(sleep)
                        dismiss()
                    }
                } label: {
                    LabeledContent {
                        SleepTimerValue(sleepsAt: sleepsAt, end: sleepsAtEnd ? endTitle : nil)
                    } label: {
                        Label("Sleep Timer", systemImage: "moon.zzz")
                    }
                }
                if let speed {
                    NavigationLink {
                        SpeedList(current: speed.current, choices: speed.choices) { rate in
                            chooseSpeed(rate)
                            dismiss()
                        }
                    } label: {
                        LabeledContent {
                            Text(WatchBookFormat.rate(speed.current))
                        } label: {
                            Label("Speed", systemImage: "gauge.with.dots.needle.67percent")
                        }
                    }
                }
            }
            .navigationTitle("Options")
        }
    }
}
