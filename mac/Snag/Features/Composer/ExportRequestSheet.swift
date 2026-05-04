import SwiftUI
import AppKit

/// Sheet to bulk-export drafts as HAR / Postman Collection. Mirrors the import
/// sheet's two-pane layout: list of drafts on the left (with checkboxes) and a
/// format picker + preview on the right.
struct ExportRequestSheet: View {
    @Binding var isPresented: Bool

    @ObservedObject private var store: RequestDraftStore = RequestDraftStore.shared

    @State private var selected: Set<String> = []
    @State private var format: ExportFormat = .har
    @State private var filter: String = ""
    @State private var errorMessage: String? = nil

    /// Bulk-capable formats only — single-draft formats use the Code tab.
    private var bulkFormats: [ExportFormat] {
        ExportFormat.allCases.filter { $0.supportsBulk }
    }

    private var filteredDrafts: [RequestDraft] {
        let q = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.drafts }
        return store.drafts.filter {
            $0.data.displayName.lowercased().contains(q) ||
            $0.data.url.lowercased().contains(q) ||
            $0.data.method.lowercased().contains(q)
        }
    }

    private var selectedDrafts: [RequestDraft] {
        store.drafts.filter { selected.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Export Requests".localized)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .padding(.bottom, 8)

            HStack(alignment: .top, spacing: 12) {
                draftList
                    .frame(maxWidth: .infinity)
                Divider()
                formatPanel
                    .frame(width: 280)
            }
            .frame(maxHeight: .infinity)

            if let err = errorMessage {
                Text(err).font(.system(size: 11)).foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button("Cancel".localized) { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button(String(format: "Export %d…".localized, selected.count)) {
                    runExport()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
            }
            .padding(.top, 8)
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 480)
    }

    private var draftList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Filter…".localized, text: $filter)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredDrafts) { draft in
                        row(draft)
                    }
                }
            }

            HStack(spacing: 12) {
                Text(String(format: "Selected: %d of %d".localized,
                            selected.count, store.drafts.count))
                Button("Select all".localized) {
                    selected = Set(filteredDrafts.map { $0.id })
                }
                Button("Select none".localized) { selected.removeAll() }
                Spacer()
            }
            .font(.system(size: 11))
        }
    }

    private func row(_ draft: RequestDraft) -> some View {
        let checked = selected.contains(draft.id)
        return HStack(spacing: 6) {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .foregroundColor(checked ? .accentColor : .secondary)
                .onTapGesture {
                    if checked { selected.remove(draft.id) }
                    else { selected.insert(draft.id) }
                }
            Text(draft.data.method.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
            Text(draft.data.displayName)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var formatPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Format".localized)
                .font(.system(size: 11, weight: .semibold))
            Picker("", selection: $format) {
                ForEach(bulkFormats) { f in
                    Text(f.displayName).tag(f)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Text("Notes".localized)
                .font(.system(size: 11, weight: .semibold))
                .padding(.top, 8)
            Text(notes)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: ThemeColor.contentBarColor))
    }

    private var notes: String {
        switch format {
        case .har:
            return "HAR captures the request only. Response objects are stub entries (status 0) since drafts have no committed run output.".localized
        case .postmanCollection:
            return "Postman Collection v2.1 — flat (no folder hierarchy). File parts keep their local paths, which only work on the original machine.".localized
        default:
            return ""
        }
    }

    // MARK: - Actions

    private func runExport() {
        errorMessage = nil
        let drafts = selectedDrafts.map { $0.data }
        guard !drafts.isEmpty else { return }

        let text: String
        do {
            text = try RequestExporters.exportBulk(drafts, as: format)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export".localized
        panel.allowedContentTypes = format == .har ? [.json, .data] : [.json]
        panel.nameFieldStringValue = defaultFilename()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                isPresented = false
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func defaultFilename() -> String {
        let base = "snag-export"
        return "\(base).\(format.fileExtension)"
    }
}
