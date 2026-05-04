import Foundation

/// One request inside an importable batch (cURL/HAR/Postman/Insomnia).
/// Already mapped to `RequestDraftData` so the picker can preview / dedupe
/// without redoing parser work.
struct ImportableRequest: Identifiable, Equatable {
    let id: UUID
    var folderPath: [String]
    var name: String
    var draftData: RequestDraftData
    var warnings: [String]
    /// Canonical method+url+headers+body hash; used for duplicate detection.
    var sourceHash: String

    init(id: UUID = UUID(),
         folderPath: [String] = [],
         name: String,
         draftData: RequestDraftData,
         warnings: [String] = []) {
        self.id = id
        self.folderPath = folderPath
        self.name = name
        self.draftData = draftData
        self.warnings = warnings
        self.sourceHash = ImportableRequest.canonicalHash(of: draftData)
    }

    /// Canonical-hash of method/url/headers/body so duplicates from different
    /// sources collide. Lowercases header *names* for the comparison only —
    /// the displayed/imported header keeps original casing.
    static func canonicalHash(of d: RequestDraftData) -> String {
        var pieces: [String] = []
        pieces.append(d.method.uppercased())
        pieces.append(d.rebuildURL())
        for h in d.headers where h.enabled && !h.key.isEmpty {
            pieces.append("H:" + h.key.lowercased() + "=" + h.value)
        }
        if d.bodyEncoding == .multipart {
            for p in d.multipartParts where p.enabled && !p.name.isEmpty {
                pieces.append("M:\(p.name)|\(p.kind.rawValue)|\(p.textValue)|\(p.fileURL ?? "")|\(p.fileName ?? "")|\(p.contentType ?? "")")
            }
        } else if let b = d.bodyBase64, !b.isEmpty {
            pieces.append("B:" + b)
        }
        return pieces.joined(separator: "\n")
    }
}

/// Folder node for tree pickers. HAR/multi-cURL produce flat trees; Postman
/// produces nested trees.
struct FolderNode: Identifiable, Equatable {
    let id: UUID
    var name: String
    var children: [FolderNode]
    /// IDs into `ImportableBatch.requests` that live directly in this folder.
    var requestIDs: [UUID]

    init(id: UUID = UUID(),
         name: String,
         children: [FolderNode] = [],
         requestIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.children = children
        self.requestIDs = requestIDs
    }
}

struct ImportableBatch: Equatable {
    let sourceLabel: String
    var requests: [ImportableRequest]
    /// Folder tree (Postman). `nil` for flat sources (HAR / multi-cURL).
    var folders: FolderNode?
}

/// Options applied when projecting a batch onto the draft store.
struct BatchImportOptions {
    enum OpenMode: Hashable {
        case openAllAsTabs
        case saveAndOpenFirst(Int)
        case saveOnly
    }

    var openMode: OpenMode = .saveAndOpenFirst(5)
    var prefixWithFolderPath: Bool = true
    var skipDuplicates: Bool = false
}

/// Outcome surface for the post-import toast / sheet summary.
struct ImportResult: Equatable {
    var imported: Int
    var skipped: Int
    var opened: Int
    var failed: Int
}

/// Input handed to a batch importer — text or a file URL. `text` lets
/// auto-detect peek without a file system read; `fileURL` carries the source
/// label for the picker header.
enum ImportInput {
    case text(String)
    case fileURL(URL)
}

extension ImportInput {
    /// Read the input as text. File reads happen here (not inside importers).
    func readText() throws -> String {
        switch self {
        case .text(let s): return s
        case .fileURL(let url): return try String(contentsOf: url, encoding: .utf8)
        }
    }

    /// User-visible label for the source — filename or "Pasted input".
    var label: String {
        switch self {
        case .text: return "Pasted input".localized
        case .fileURL(let url): return url.lastPathComponent
        }
    }
}

/// Top-level error class for batch importers (single-cURL keeps using
/// `CurlParseError`).
enum ImportError: LocalizedError {
    case unrecognizedFormat
    case malformedJSON(String)
    case unsupportedSchema(version: String)
    case emptyBatch

    var errorDescription: String? {
        switch self {
        case .unrecognizedFormat:
            return "Unrecognized import format.".localized
        case .malformedJSON(let s):
            return "Malformed JSON: \(s)".localized
        case .unsupportedSchema(let v):
            return "Unsupported schema version: \(v)".localized
        case .emptyBatch:
            return "The file parsed but contained no requests.".localized
        }
    }
}

/// Conformance for every batch importer (HAR / Postman / multi-cURL / Insomnia).
protocol BatchImporter {
    static func canHandle(_ input: ImportInput) -> Bool
    static func parse(_ input: ImportInput,
                      options: CurlImportOptions) throws -> ImportableBatch
}
