import SwiftUI
import AppKit

struct MultipartEditorView: View {
    @ObservedObject var draft: RequestDraft

    @State private var trailingId: String = UUID().uuidString

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(displayRows) { row in
                        MultipartRow(
                            row: row,
                            isSynthetic: row.id == trailingId,
                            update: { updated in update(rowId: row.id, with: updated) },
                            remove: { remove(rowId: row.id) }
                        )
                        Divider()
                    }
                }
            }

            HStack {
                Button(action: addRow) {
                    Label("Add Part".localized, systemImage: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)

                Spacer()

                Text(sizeLabel)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: ThemeColor.contentBarColor))
        }
    }

    private var rows: [DraftMultipartPart] { draft.data.multipartParts }

    private var displayRows: [DraftMultipartPart] {
        let real = rows
        if let last = real.last, last.name.isEmpty && last.textValue.isEmpty && last.fileURL == nil {
            return real
        }
        return real + [DraftMultipartPart(id: trailingId)]
    }

    private var sizeLabel: String {
        var bytes = 0
        for p in rows where p.enabled && !p.name.isEmpty {
            switch p.kind {
            case .text: bytes += p.textValue.utf8.count
            case .file:
                if let s = p.fileURL,
                   let url = URL(string: s),
                   url.isFileURL,
                   let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? NSNumber {
                    bytes += size.intValue
                }
            }
        }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func addRow() {
        var arr = rows
        arr.append(DraftMultipartPart())
        write(arr)
    }

    private func remove(rowId: String) {
        var arr = rows
        arr.removeAll { $0.id == rowId }
        write(arr)
    }

    private func update(rowId: String, with new: DraftMultipartPart) {
        if rowId == trailingId {
            var materialized = new
            materialized.id = UUID().uuidString
            var arr = rows
            arr.append(materialized)
            trailingId = UUID().uuidString
            write(arr)
            return
        }
        var arr = rows
        guard let idx = arr.firstIndex(where: { $0.id == rowId }), arr[idx] != new else { return }
        arr[idx] = new
        write(arr)
    }

    private func write(_ arr: [DraftMultipartPart]) {
        draft.data.multipartParts = arr
        RequestDraftStore.shared.scheduleSave(draft)
    }
}

private struct MultipartRow: View {
    let row: DraftMultipartPart
    let isSynthetic: Bool
    let update: (DraftMultipartPart) -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Toggle("", isOn: Binding(
                get: { row.enabled },
                set: { var r = row; r.enabled = $0; update(r) }
            ))
            .labelsHidden()
            .opacity(isSynthetic ? 0 : 1)
            .disabled(isSynthetic)

            Picker("", selection: Binding(
                get: { row.kind },
                set: { var r = row; r.kind = $0; update(r) }
            )) {
                Text("Text".localized).tag(DraftMultipartPartKind.text)
                Text("File".localized).tag(DraftMultipartPartKind.file)
            }
            .pickerStyle(MenuPickerStyle())
            .labelsHidden()
            .frame(width: 70)

            TextField("Name".localized, text: Binding(
                get: { row.name },
                set: { var r = row; r.name = $0; update(r) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .frame(width: 140, alignment: .leading)

            Divider().frame(height: 14)

            switch row.kind {
            case .text:
                TextField("Value".localized, text: Binding(
                    get: { row.textValue },
                    set: { var r = row; r.textValue = $0; update(r) }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 11))
            case .file:
                Button(action: chooseFile) {
                    Label(fileButtonTitle, systemImage: "doc")
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isSynthetic {
                Color.clear.frame(width: 16, height: 16)
            } else {
                Button(action: remove) {
                    Image(systemName: "minus.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .opacity(row.enabled ? 1.0 : 0.5)
    }

    private var fileButtonTitle: String {
        if let s = row.fileURL, let url = URL(string: s) {
            return row.fileName ?? url.lastPathComponent
        }
        return "Choose File…".localized
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var r = row
        r.fileURL = url.absoluteString
        r.fileName = url.lastPathComponent
        if r.contentType?.nilIfEmpty == nil {
            r.contentType = url.mimeType
        }
        if r.name.isEmpty {
            r.name = url.deletingPathExtension().lastPathComponent
        }
        update(r)
    }
}
