import SwiftUI
import AppKit

/// The Composer's "Code" tab — left-hand format sidebar + right-hand snippet
/// preview with Copy / Save…  actions and a small status footer. Replaces the
/// older single-format `DraftCurlPreviewView`.
struct DraftCodeView: View {
    @ObservedObject var draft: RequestDraft
    @AppStorage(SnagConstants.composerCodePreferredFormatKey)
    private var storedFormat: String = ExportFormat.curl.rawValue

    private var selection: Binding<ExportFormat> {
        Binding(
            get: { ExportFormat(rawValue: storedFormat) ?? .curl },
            set: { storedFormat = $0.rawValue }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            CodeFormatSidebar(selection: selection)

            Divider()

            VStack(spacing: 0) {
                headerBar
                Divider()
                CodeTextView(text: snippet)
                    .padding(.vertical, 4)
                Divider()
                statusFooter
            }
        }
    }

    // MARK: - Header bar

    private var headerBar: some View {
        HStack(spacing: 8) {
            Spacer()
            Button(action: copyToPasteboard) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                    Text("Copy".localized)
                }
                .font(.system(size: 11))
            }
            .help("Copy snippet to clipboard".localized)

            Button(action: saveToFile) {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Save…".localized)
                }
                .font(.system(size: 11))
            }
            .help("Save snippet to a file".localized)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: ThemeColor.contentBarColor))
    }

    // MARK: - Status footer

    private var statusFooter: some View {
        HStack(spacing: 12) {
            Text(headerCountSummary)
            Text(bodySizeSummary)
            if filePartCount > 0 {
                Text(filePartSummary)
            }
            Spacer()
        }
        .font(.system(size: 10))
        .foregroundColor(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(nsColor: ThemeColor.contentBarColor))
    }

    // MARK: - Snippet

    private var snippet: String {
        RequestExporters.export(draft.data, as: selection.wrappedValue)
    }

    // MARK: - Status helpers

    private var enabledHeaderCount: Int {
        draft.data.headers.filter { $0.enabled && !$0.key.isEmpty }.count
    }

    private var headerCountSummary: String {
        let n = enabledHeaderCount
        return n == 1
            ? "1 header".localized
            : String(format: "%d headers".localized, n)
    }

    private var bodySizeSummary: String {
        let bytes: Int = {
            if draft.data.bodyEncoding == .multipart { return 0 }
            guard let b64 = draft.data.bodyBase64,
                  let data = Data(base64Encoded: b64) else { return 0 }
            return data.count
        }()
        return String(format: "%@ body".localized, formatByteCount(bytes))
    }

    private var filePartCount: Int {
        draft.data.multipartParts.filter { $0.enabled && $0.kind == .file }.count
    }

    private var filePartSummary: String {
        let n = filePartCount
        return n == 1
            ? "1 file part".localized
            : String(format: "%d file parts".localized, n)
    }

    private func formatByteCount(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    // MARK: - Actions

    private func copyToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(snippet, forType: .string)
    }

    private func saveToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = []
        panel.canCreateDirectories = true
        panel.title = "Save Snippet".localized
        panel.nameFieldStringValue = defaultFilename()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try snippet.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    private func defaultFilename() -> String {
        let base = draft.data.displayName
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = base.isEmpty ? "Snag-Snippet" : base
        return "\(safe).\(selection.wrappedValue.fileExtension)"
    }
}
