import Foundation

/// Categoría visual fija: mismo tipo → mismo icono (independiente del icono del sistema).
public enum FileCategory: String, Codable, Sendable, CaseIterable, Comparable {
    case folder
    case video
    case audio
    case image
    case pdf
    case word
    case excel
    case powerpoint
    case text
    case code
    case archive
    case diskImage
    case app
    case other

    /// Orden al agrupar/ordenar por tipo (carpetas primero vía foldersFirst; esto ordena archivos).
    public var sortIndex: Int {
        switch self {
        case .folder: return 0
        case .video: return 1
        case .audio: return 2
        case .image: return 3
        case .pdf: return 4
        case .word: return 5
        case .excel: return 6
        case .powerpoint: return 7
        case .text: return 8
        case .code: return 9
        case .archive: return 10
        case .diskImage: return 11
        case .app: return 12
        case .other: return 13
        }
    }

    public var labelSpanish: String {
        switch self {
        case .folder: return "Carpeta"
        case .video: return "Vídeo"
        case .audio: return "Audio"
        case .image: return "Imagen"
        case .pdf: return "PDF"
        case .word: return "Word"
        case .excel: return "Excel"
        case .powerpoint: return "PowerPoint"
        case .text: return "Texto"
        case .code: return "Código"
        case .archive: return "Archivo comprimido"
        case .diskImage: return "Imagen de disco"
        case .app: return "App"
        case .other: return "Otro"
        }
    }

    public var labelEnglish: String {
        switch self {
        case .folder: return "Folder"
        case .video: return "Video"
        case .audio: return "Audio"
        case .image: return "Image"
        case .pdf: return "PDF"
        case .word: return "Word"
        case .excel: return "Excel"
        case .powerpoint: return "PowerPoint"
        case .text: return "Text"
        case .code: return "Code"
        case .archive: return "Archive"
        case .diskImage: return "Disk Image"
        case .app: return "Application"
        case .other: return "Other"
        }
    }

    public var labelLocalized: String {
        L10n.isEnglish ? labelEnglish : labelSpanish
    }

    /// Nombre de carpeta al organizar por tipo (fase 5).
    public var organizeFolderName: String {
        switch self {
        case .folder: return "Carpetas"
        case .video: return "Vídeos"
        case .audio: return "Audio"
        case .image: return "Imágenes"
        case .pdf: return "PDFs"
        case .word: return "Word"
        case .excel: return "Excel"
        case .powerpoint: return "PowerPoint"
        case .text: return "Texto"
        case .code: return "Código"
        case .archive: return "Comprimidos"
        case .diskImage: return "Discos"
        case .app: return "Apps"
        case .other: return "Otros"
        }
    }

    public var organizeFolderNameEnglish: String {
        switch self {
        case .folder: return "Folders"
        case .video: return "Videos"
        case .audio: return "Audio"
        case .image: return "Images"
        case .pdf: return "PDFs"
        case .word: return "Word"
        case .excel: return "Excel"
        case .powerpoint: return "PowerPoint"
        case .text: return "Text"
        case .code: return "Code"
        case .archive: return "Archives"
        case .diskImage: return "Disk Images"
        case .app: return "Apps"
        case .other: return "Other"
        }
    }

    public var organizeFolderNameLocalized: String {
        L10n.isEnglish ? organizeFolderNameEnglish : organizeFolderName
    }

    /// SF Symbol estable por categoría (misma pinta siempre).
    public var symbolName: String {
        switch self {
        case .folder: return "folder.fill"
        case .video: return "film"
        case .audio: return "waveform"
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .word: return "doc.text.fill"
        case .excel: return "tablecells"
        case .powerpoint: return "rectangle.on.rectangle.angled"
        case .text: return "doc.plaintext"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .archive: return "archivebox.fill"
        case .diskImage: return "opticaldisc"
        case .app: return "app.gift"
        case .other: return "doc"
        }
    }

    /// Tinte semántico para reconocer el tipo de un vistazo.
    public var tintHex: String {
        switch self {
        case .folder: return "8B9CFF"
        case .video: return "FF6B6B"
        case .audio: return "C084FC"
        case .image: return "34D399"
        case .pdf: return "F87171"
        case .word: return "60A5FA"
        case .excel: return "4ADE80"
        case .powerpoint: return "FB923C"
        case .text: return "A1A1AA"
        case .code: return "22D3EE"
        case .archive: return "FBBF24"
        case .diskImage: return "A78BFA"
        case .app: return "94A3B8"
        case .other: return "71717A"
        }
    }

    public static func < (lhs: FileCategory, rhs: FileCategory) -> Bool {
        lhs.sortIndex < rhs.sortIndex
    }

    public static func classify(fileName: String, isDirectory: Bool) -> FileCategory {
        if isDirectory { return .folder }
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return .other }

        if Self.videoExt.contains(ext) { return .video }
        if Self.audioExt.contains(ext) { return .audio }
        if Self.imageExt.contains(ext) { return .image }
        if Self.pdfExt.contains(ext) { return .pdf }
        if Self.wordExt.contains(ext) { return .word }
        if Self.excelExt.contains(ext) { return .excel }
        if Self.powerpointExt.contains(ext) { return .powerpoint }
        if Self.textExt.contains(ext) { return .text }
        if Self.codeExt.contains(ext) { return .code }
        if Self.archiveExt.contains(ext) { return .archive }
        if Self.diskExt.contains(ext) { return .diskImage }
        if Self.appExt.contains(ext) { return .app }
        return .other
    }

    private static let videoExt: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv", "flv", "mpeg", "mpg", "m2ts", "ts"
    ]
    private static let audioExt: Set<String> = [
        "mp3", "wav", "aac", "m4a", "flac", "aiff", "aif", "ogg", "wma", "caf"
    ]
    private static let imageExt: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp", "svg", "ico", "raw", "cr2", "nef"
    ]
    private static let pdfExt: Set<String> = ["pdf"]
    private static let wordExt: Set<String> = ["doc", "docx", "rtf", "pages", "odt"]
    private static let excelExt: Set<String> = ["xls", "xlsx", "csv", "numbers", "ods", "tsv"]
    private static let powerpointExt: Set<String> = ["ppt", "pptx", "key", "odp"]
    private static let textExt: Set<String> = ["txt", "md", "markdown", "text", "log", "rtfd"]
    private static let codeExt: Set<String> = [
        "swift", "ts", "tsx", "js", "jsx", "py", "rs", "go", "java", "kt", "c", "h", "cpp", "hpp",
        "m", "mm", "css", "scss", "html", "htm", "json", "yml", "yaml", "toml", "xml", "sql",
        "sh", "zsh", "bash", "rb", "php", "mq4", "mq5", "ex4", "ex5"
    ]
    private static let archiveExt: Set<String> = ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz"]
    private static let diskExt: Set<String> = ["dmg", "iso", "img", "toast", "pkg"]
    private static let appExt: Set<String> = ["app", "ipa"]
}
