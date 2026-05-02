import Foundation
import UniformTypeIdentifiers

extension URL {
    /// MIME type derived from the URL's path extension. Falls back to
    /// `application/octet-stream` when the extension is unknown or absent.
    var mimeType: String {
        if let utt = UTType(filenameExtension: pathExtension), let mime = utt.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }
}
