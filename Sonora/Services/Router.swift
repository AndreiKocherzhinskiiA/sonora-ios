import Foundation
import Observation

/// Where the current tab's navigation stack is, so a sheet or a menu can open an artist or an album
/// without owning a navigation link.
@Observable
final class Router {
    var path: [YouTubeDestination] = []
    /// Set when a destination is opened from the full-screen player, which then closes itself.
    var closesPlayer = false

    func open(_ destination: YouTubeDestination, fromPlayer: Bool = false) {
        path.append(destination)
        closesPlayer = fromPlayer
    }
}
