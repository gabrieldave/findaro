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
    /// Último acceso (Finder «Fecha de última apertura»). `distantPast` si el FS no lo da.
    public let dateLastOpened: Date
    public let kind: String

    public init(
        path: String,
        name: String,
        isDirectory: Bool,
        size: Int64,
        dateModified: Date,
        dateCreated: Date,
        dateAdded: Date,
        dateLastOpened: Date = .distantPast,
        kind: String
    ) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.dateModified = dateModified
        self.dateCreated = dateCreated
        self.dateAdded = dateAdded
        self.dateLastOpened = dateLastOpened
        self.kind = kind
    }

    /// Categoría visual estable (mismo tipo → mismo icono).
    public var category: FileCategory {
        FileCategory.classify(fileName: name, isDirectory: isDirectory)
    }
}
