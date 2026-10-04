/// Stable account identifiers, independent of image rendering and localization.
enum ProfileAvatar: String, CaseIterable, Identifiable, Sendable {
    case vigilant, cosmic, robot
    var id: String { rawValue }
}
