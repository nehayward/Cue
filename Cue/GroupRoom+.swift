import SonosKit

extension GroupRoom {
    /// Lowest-percentage battery among any battery-powered room in the
    /// group, or nil for AC-only groups. Used as the single source of truth
    /// for group-level battery indicators (toolbar subtitle, Speakers row,
    /// menu bar info) so a battery speaker grouped under an AC coordinator
    /// — e.g. a Move grouped with a SPA — still surfaces its charge state.
    /// The lowest battery is what matters: it's the one that will drop out
    /// of the group first.
    var lowestBattery: Battery? {
        rooms.compactMap(\.battery).min(by: { $0.percentage < $1.percentage })
    }
}
