import SwiftUI

struct EditableKeyValueListView: View {
    @ObservedObject var draft: RequestDraft
    let keyPath: WritableKeyPath<RequestDraftData, [DraftKeyValue]>
    let onURLRebuildNeeded: Bool   // when true, edits trigger URL rebuild (Params tab)

    /// Stable id for the synthetic trailing empty row. Materialized on first edit.
    @State private var trailingId: String = UUID().uuidString

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(displayRows) { row in
                        EditableKeyValueRow(
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
                    Label("Add Row".localized, systemImage: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: ThemeColor.contentBarColor))
        }
    }

    private var rows: [DraftKeyValue] { draft.data[keyPath: keyPath] }

    /// Persisted rows + a synthetic trailing empty row that lets users start typing
    /// immediately. The trailing row is only persisted on first edit. If the last
    /// persisted row is already empty, no synthetic row is added.
    private var displayRows: [DraftKeyValue] {
        let real = rows
        if let last = real.last, last.key.isEmpty && last.value.isEmpty {
            return real
        }
        return real + [DraftKeyValue(id: trailingId)]
    }

    private func addRow() {
        var arr = rows
        arr.append(DraftKeyValue())
        write(arr)
    }

    private func remove(rowId: String) {
        var arr = rows
        arr.removeAll { $0.id == rowId }
        write(arr)
    }

    private func update(rowId: String, with new: DraftKeyValue) {
        if rowId == trailingId {
            // First edit on the synthetic row — materialize it with a real id and
            // rotate the placeholder so a new blank row appears below it.
            var materialized = new
            materialized.id = UUID().uuidString
            var arr = rows
            arr.append(materialized)
            trailingId = UUID().uuidString
            write(arr)
            return
        }

        var arr = rows
        if let idx = arr.firstIndex(where: { $0.id == rowId }) {
            arr[idx] = new
            write(arr)
        }
    }

    private func write(_ arr: [DraftKeyValue]) {
        draft.data[keyPath: keyPath] = arr
        if onURLRebuildNeeded {
            draft.data.url = draft.data.rebuildURL()
        }
        RequestDraftStore.shared.scheduleSave(draft)
    }
}

private struct EditableKeyValueRow: View {
    let row: DraftKeyValue
    let isSynthetic: Bool
    let update: (DraftKeyValue) -> Void
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

            TextField("Key".localized, text: Binding(
                get: { row.key },
                set: { var r = row; r.key = $0; update(r) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .frame(width: 180, alignment: .leading)

            Divider().frame(height: 14)

            TextField("Value".localized, text: Binding(
                get: { row.value },
                set: { var r = row; r.value = $0; update(r) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 11))

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
}
