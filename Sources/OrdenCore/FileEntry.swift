import Foundation

public struct FileEntry: Equatable, Sendable, Identifiable, Hashable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let isDirectory: Bool
    public let size: Int64
    public let dateModified: Date
    public let dateCreated: Date
    public let dateAdded: Date
    public let kind: String

    public init(
        path: String,
        name: String,
        isDirectory: Bool,
        size: Int64,
        dateModified: Date,
        dateCreated: Date,
        dateAdded: Date,
        kind: String
    ) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.dateModified = dateModified
        self.dateCreated = dateCreated
        self.dateAdded = dateAdded
        self.kind = kind
    }
}
