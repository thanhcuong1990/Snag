import Foundation

/// Parses input that contains more than one `curl ...` command. Phase 3 splits
/// on **blank lines**; quote-aware line-start splitting can replace this once
/// the tokenizer learns to detect command boundaries safely. Bad chunks are
/// surfaced as warning rows rather than aborting the whole batch.
enum MultiCurlImporter: BatchImporter {

    static func canHandle(_ input: ImportInput) -> Bool {
        guard let text = try? input.readText() else { return false }
        return curlCommandCount(text) >= 2
    }

    static func parse(_ input: ImportInput,
                      options: CurlImportOptions) throws -> ImportableBatch {
        let text = try input.readText()
        let chunks = splitBlankLine(text).filter { !$0.isEmpty }

        var requests: [ImportableRequest] = []
        for (i, chunk) in chunks.enumerated() {
            let label = String(format: "Request %d".localized, i + 1)
            do {
                let result = try CurlImporter.parse(chunk, options: options)
                requests.append(ImportableRequest(
                    name: label,
                    draftData: result.draft,
                    warnings: result.warnings
                ))
            } catch {
                // One bad chunk doesn't kill the batch — surface as a placeholder
                // row so the user can see the failure and choose to skip it.
                let placeholder = RequestDraftData(name: label, url: "", method: "GET")
                let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                requests.append(ImportableRequest(
                    name: label,
                    draftData: placeholder,
                    warnings: ["Parse error: \(msg)"]
                ))
            }
        }

        if requests.isEmpty { throw ImportError.emptyBatch }

        return ImportableBatch(
            sourceLabel: input.label,
            requests: requests,
            folders: nil
        )
    }

    // MARK: - Detection helpers

    /// Count distinct `curl` invocations in the input. Conservative: looks at
    /// blank-line-separated chunks and checks each begins with `curl `.
    static func curlCommandCount(_ text: String) -> Int {
        let chunks = splitBlankLine(text)
        var count = 0
        for c in chunks where chunkStartsWithCurl(c) {
            count += 1
        }
        return count
    }

    private static func chunkStartsWithCurl(_ chunk: String) -> Bool {
        let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()
        return lower == "curl" || lower.hasPrefix("curl ") || lower.hasPrefix("curl\t") ||
               lower.hasPrefix("curl\n") || lower.hasPrefix("curl\\")
    }

    /// Split on runs of blank lines (≥1 fully blank line). Preserves line
    /// continuations (`\` + newline) inside a single chunk.
    private static func splitBlankLine(_ text: String) -> [String] {
        var chunks: [String] = []
        var current: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !current.isEmpty {
                    chunks.append(current.joined(separator: "\n"))
                    current.removeAll(keepingCapacity: true)
                }
            } else {
                current.append(String(line))
            }
        }
        if !current.isEmpty {
            chunks.append(current.joined(separator: "\n"))
        }
        return chunks
    }
}
