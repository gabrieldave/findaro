import Foundation
import OrdenCore

@MainActor
final class SharedShelf {
    static let shared = SharedShelf()
    static let didChangeNotification = Notification.Name("findaroSharedShelfDidChange")

    var items: [FileOps.ShelfItem] = []
}
