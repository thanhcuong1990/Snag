import Foundation

/// Where `MainView` should route. Replaces the older `SnagController.MainTab`.
/// The active draft id is owned by `ComposerController.activeDraftId`,
/// not carried in the route, to avoid two sources of truth.
enum MainContentRoute: Equatable {
    case network
    case logs
    case saved
    case compose
}
