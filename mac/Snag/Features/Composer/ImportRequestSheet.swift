import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Two-stage import sheet:
/// - Stage 1: paste / drop / pick a file. Auto-detect surfaces the format.
/// - Stage 2: when N > 1, show a picker to choose which requests to import.
///   For Postman, the picker is a folder tree; otherwise it's a flat list.
struct ImportRequestSheet: View {
    @Binding var isPresented: Bool

    @State private var input: String = ""
    @State private var sourceFileURL: URL? = nil
    @State private var loadLocalFiles: Bool = false
    @State private var replaceActive: Bool = false
    @State private var errorMessage: String? = nil
    @State private var stage: Stage = .source

    // Detection / preview state
    @State private var detection: DetectedFormat = .unknown
    @State private var batch: ImportableBatch? = nil

    // Picker state
    @State private var selected: Set<UUID> = []
    @State private var filter: String = ""
    @State private var detailRequestID: UUID? = nil
    @State private var openMode: BatchImportOptions.OpenMode = .saveAndOpenFirst(5)
    @State private var prefixWithFolderPath: Bool = true
    @State private var skipDuplicates: Bool = false

    // Result toast
    @State private var resultMessage: String? = nil

    private enum Stage { case source, picker, done }

    var body: some View {
        VStack(spacing: 0) {
            switch stage {
            case .source: stage1
            case .picker: stage2
            case .done: stageDone
            }
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 560)
    }

    // MARK: - Stage 1: source

    private var stage1: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Import Requests".localized)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(detectionLabel)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Text("Drop a .har / .json file here, or paste below:".localized)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            TextEditor(text: $input)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 280)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .onChange(of: input) { _ in
                    sourceFileURL = nil
                    refreshDetection()
                }
                .onDrop(of: [UTType.fileURL], isTargeted: nil, perform: handleDrop)

            HStack(spacing: 8) {
                Button("Choose File…".localized) { chooseFile() }
                Toggle("Load local files".localized, isOn: $loadLocalFiles)
                    .toggleStyle(.checkbox)
                    .help("Read files referenced by @path. Off by default — pasted curl can be untrusted.".localized)

                Toggle("Replace active draft".localized, isOn: $replaceActive)
                    .toggleStyle(.checkbox)
                    .disabled(detection != .singleCurl ||
                              ComposerController.shared.activeDraft == nil)
                Spacer()
            }

            if let err = errorMessage {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button("Cancel".localized) { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button(continueButtonTitle) { advance() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(detection == .unknown)
            }
        }
    }

    private var detectionLabel: String {
        switch detection {
        case .singleCurl: return "Detected: cURL (1 request)".localized
        case .multiCurl:
            let n = MultiCurlImporter.curlCommandCount(input)
            return String(format: "Detected: cURL (%d requests)".localized, n)
        case .postmanCollection: return "Detected: Postman Collection".localized
        case .har: return "Detected: HAR".localized
        case .rawHTTP: return "Detected: Raw HTTP".localized
        case .unknown:
            return input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? ""
                : "Unrecognized format".localized
        }
    }

    private var continueButtonTitle: String {
        switch detection {
        case .singleCurl: return "Import".localized
        default: return "Continue".localized
        }
    }

    // MARK: - Stage 2: picker

    private var stage2: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(format: "Import — %@ (%d requests)".localized,
                            batch?.sourceLabel ?? "",
                            batch?.requests.count ?? 0))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Filter…".localized, text: $filter)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))

            HStack(alignment: .top, spacing: 0) {
                pickerList
                    .frame(maxWidth: .infinity)

                Divider()

                detailPane
                    .frame(width: 280)
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 12) {
                Text(String(format: "Selected: %d of %d".localized,
                            selected.count,
                            batch?.requests.count ?? 0))
                Button("Select all".localized) { selectAll() }
                Button("Select none".localized) { selected.removeAll() }
                Button("Invert".localized) { invertSelection() }
                Spacer()
            }
            .font(.system(size: 11))

            VStack(alignment: .leading, spacing: 4) {
                Text("Open in composer:".localized)
                    .font(.system(size: 11, weight: .semibold))
                Picker("", selection: $openMode) {
                    Text("Open all as tabs".localized)
                        .tag(BatchImportOptions.OpenMode.openAllAsTabs)
                    Text("Save to drafts, open first 5".localized)
                        .tag(BatchImportOptions.OpenMode.saveAndOpenFirst(5))
                    Text("Save to drafts only".localized)
                        .tag(BatchImportOptions.OpenMode.saveOnly)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            HStack(spacing: 16) {
                Toggle("Use folder path as prefix".localized, isOn: $prefixWithFolderPath)
                    .toggleStyle(.checkbox)
                Toggle("Skip duplicates".localized, isOn: $skipDuplicates)
                    .toggleStyle(.checkbox)
                Spacer()
            }

            if let err = errorMessage {
                Text(err).font(.system(size: 11)).foregroundColor(.red)
            }

            HStack {
                Button("Back".localized) { stage = .source }
                Spacer()
                Button("Cancel".localized) { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button(String(format: "Import (%d)".localized, selected.count)) {
                    performBatchImport()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
            }
        }
    }

    private var pickerList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let folders = batch?.folders {
                    folderTreeView(folders, depth: 0)
                } else {
                    flatList
                }
            }
        }
    }

    @ViewBuilder
    private var flatList: some View {
        if let batch = batch {
            ForEach(filteredRequests(in: batch.requests)) { req in
                requestRow(req, depth: 0)
            }
        }
    }

    private func folderTreeView(_ node: FolderNode, depth: Int) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 0) {
                if depth > 0 {
                    folderRow(node, depth: depth)
                }

                ForEach(node.requestIDs, id: \.self) { reqID in
                    if let req = batch?.requests.first(where: { $0.id == reqID }),
                       matchesFilter(req) {
                        requestRow(req, depth: depth + 1)
                    }
                }

                ForEach(node.children) { child in
                    folderTreeView(child, depth: depth + 1)
                }
            }
        )
    }

    private func folderRow(_ node: FolderNode, depth: Int) -> some View {
        let descendantIDs = collectDescendantRequestIDs(node)
        let allSelected = !descendantIDs.isEmpty &&
                          descendantIDs.allSatisfy { selected.contains($0) }
        let anySelected = descendantIDs.contains { selected.contains($0) }
        return HStack(spacing: 6) {
            Image(systemName: allSelected ? "checkmark.square.fill" :
                              (anySelected ? "minus.square.fill" : "square"))
                .foregroundColor(allSelected || anySelected ? .accentColor : .secondary)
                .onTapGesture { toggleFolder(descendantIDs, allSelected: allSelected) }
            Image(systemName: "folder")
                .foregroundColor(.secondary)
            Text(node.name)
                .font(.system(size: 12, weight: .semibold))
            Spacer()
        }
        .padding(.leading, CGFloat(depth) * 16)
        .padding(.vertical, 2)
    }

    private func requestRow(_ req: ImportableRequest, depth: Int) -> some View {
        let isChecked = selected.contains(req.id)
        let isFocused = detailRequestID == req.id
        return HStack(spacing: 6) {
            Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                .foregroundColor(isChecked ? .accentColor : .secondary)
                .onTapGesture { toggleRequest(req.id) }
            Text(req.draftData.method.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
            Text(req.name)
                .font(.system(size: 12))
                .lineLimit(1)
            if !req.warnings.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 9))
            }
            Spacer()
        }
        .padding(.leading, CGFloat(depth) * 16)
        .padding(.vertical, 2)
        .background(isFocused ? Color(nsColor: .selectedControlColor).opacity(0.3) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { detailRequestID = req.id }
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let req = currentDetailRequest {
                Text("\(req.draftData.method.uppercased()) \(req.draftData.url)")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(2)

                Text(String(format: "Headers (%d)".localized,
                            req.draftData.headers.count))
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.top, 4)
                ForEach(req.draftData.headers.prefix(8), id: \.id) { h in
                    Text("\(h.key): \(h.value)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                if !req.draftData.multipartParts.isEmpty {
                    Text(String(format: "Multipart (%d)".localized,
                                req.draftData.multipartParts.count))
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.top, 4)
                    ForEach(req.draftData.multipartParts, id: \.id) { p in
                        Text(p.name + " (" + p.kind.rawValue + ")")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                if !req.warnings.isEmpty {
                    Text("Warnings".localized)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.orange)
                        .padding(.top, 4)
                    ForEach(req.warnings, id: \.self) { w in
                        Text("⚠︎ " + w)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            } else {
                Text("Select a request to preview".localized)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: ThemeColor.contentBarColor))
    }

    // MARK: - Stage Done

    private var stageDone: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Import complete".localized)
                .font(.system(size: 14, weight: .semibold))
            if let m = resultMessage {
                Text(m).font(.system(size: 11))
            }
            Spacer()
            HStack {
                Spacer()
                Button("Done".localized) { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Logic

    private var currentDetailRequest: ImportableRequest? {
        guard let id = detailRequestID else {
            return batch?.requests.first
        }
        return batch?.requests.first(where: { $0.id == id })
    }

    private func filteredRequests(in requests: [ImportableRequest]) -> [ImportableRequest] {
        let q = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return requests }
        return requests.filter { matchesFilter($0, q: q) }
    }

    private func matchesFilter(_ req: ImportableRequest) -> Bool {
        let q = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        return matchesFilter(req, q: q)
    }

    private func matchesFilter(_ req: ImportableRequest, q: String) -> Bool {
        if req.name.lowercased().contains(q) { return true }
        if req.draftData.url.lowercased().contains(q) { return true }
        if req.draftData.method.lowercased().contains(q) { return true }
        return false
    }

    private func collectDescendantRequestIDs(_ node: FolderNode) -> [UUID] {
        var ids = node.requestIDs
        for c in node.children { ids.append(contentsOf: collectDescendantRequestIDs(c)) }
        return ids
    }

    private func toggleRequest(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func toggleFolder(_ ids: [UUID], allSelected: Bool) {
        if allSelected {
            for id in ids { selected.remove(id) }
        } else {
            for id in ids { selected.insert(id) }
        }
    }

    private func selectAll() {
        guard let batch = batch else { return }
        selected = Set(batch.requests.map { $0.id })
    }

    private func invertSelection() {
        guard let batch = batch else { return }
        let all = Set(batch.requests.map { $0.id })
        selected = all.subtracting(selected)
    }

    // MARK: - Actions

    private func refreshDetection() {
        errorMessage = nil
        let inp: ImportInput = sourceFileURL.map { .fileURL($0) } ?? .text(input)
        detection = RequestImporters.detect(inp)
    }

    private func advance() {
        errorMessage = nil
        let inp: ImportInput = sourceFileURL.map { .fileURL($0) } ?? .text(input)

        if detection == .singleCurl, replaceActive,
           ComposerController.shared.activeDraft != nil {
            // Single-cURL replace-active: skip the picker entirely.
            do {
                let opts = CurlImportOptions(loadLocalFiles: loadLocalFiles)
                let r = try CurlImporter.parse(input, options: opts)
                ComposerController.shared.importDraft(r.draft, replaceActive: true)
                isPresented = false
            } catch {
                errorMessage = errorDescription(error)
            }
            return
        }

        do {
            let opts = CurlImportOptions(loadLocalFiles: loadLocalFiles)
            let parsedBatch = try RequestImporters.parse(inp, options: opts)
            batch = parsedBatch

            // Default selection: everything selected.
            selected = Set(parsedBatch.requests.map { $0.id })
            detailRequestID = parsedBatch.requests.first?.id

            // Single-request: skip the picker, import straight away.
            if parsedBatch.requests.count == 1 {
                let only = parsedBatch.requests[0]
                ComposerController.shared.importDraft(only.draftData, replaceActive: false)
                isPresented = false
                return
            }

            // Set sensible default open mode based on size.
            openMode = parsedBatch.requests.count <= 5
                ? .openAllAsTabs
                : .saveAndOpenFirst(5)

            stage = .picker
        } catch {
            errorMessage = errorDescription(error)
        }
    }

    private func performBatchImport() {
        errorMessage = nil
        guard let batch = batch else { return }

        // Hard cap: confirm before opening >50 tabs.
        let willOpen: Int = {
            switch openMode {
            case .openAllAsTabs: return selected.count
            case .saveAndOpenFirst(let n): return min(n, selected.count)
            case .saveOnly: return 0
            }
        }()
        if willOpen > 50 {
            let alert = NSAlert()
            alert.messageText = String(format: "Open %d tabs?".localized, willOpen)
            alert.informativeText = "Opening many tabs may make the composer hard to navigate.".localized
            alert.addButton(withTitle: "Open All".localized)
            alert.addButton(withTitle: "Save Only".localized)
            alert.addButton(withTitle: "Cancel".localized)
            switch alert.runModal() {
            case .alertFirstButtonReturn: break
            case .alertSecondButtonReturn: openMode = .saveOnly
            default: return
            }
        }

        let options = BatchImportOptions(
            openMode: openMode,
            prefixWithFolderPath: prefixWithFolderPath,
            skipDuplicates: skipDuplicates
        )
        let result = ComposerController.shared.importBatch(
            batch,
            selected: selected,
            options: options
        )

        resultMessage = String(
            format: "Imported %d request(s); skipped %d; opened %d.".localized,
            result.imported, result.skipped, result.opened
        )
        stage = .done
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json, .text, .data]
        panel.title = "Select a file to import".localized
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            loadFileForInput(url)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url = url else { return }
            DispatchQueue.main.async { loadFileForInput(url) }
        }
        return true
    }

    private func loadFileForInput(_ url: URL) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            sourceFileURL = url
            input = text
            refreshDetection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func errorDescription(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "\(error)"
    }
}
