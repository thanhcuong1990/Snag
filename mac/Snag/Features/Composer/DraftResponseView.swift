import SwiftUI

struct DraftResponseView: View {
    @ObservedObject var draft: RequestDraft
    @ObservedObject var sender: RequestSender = RequestSender.shared
    @State private var selectedTab: ResponseTab = .body
    @State private var jsonRaw: Bool = false

    enum ResponseTab: Hashable { case body, headers }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Response".localized)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            if let status = draft.lastRun?.statusCode {
                statusBadge(status)
            }

            if let duration = draft.lastRun?.durationMS {
                Text(OverviewRepresentation.formatDuration(duration))
                    .font(.system(size: 10).monospaced())
                    .foregroundColor(.secondary)
            }

            if draft.lastRun?.responseBodyTruncated == true {
                Text("(truncated)".localized)
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            }

            Spacer()

            TabButton(title: "Body".localized,
                      isSelected: selectedTab == .body) { selectedTab = .body }
            TabButton(title: "Headers".localized,
                      isSelected: selectedTab == .headers) { selectedTab = .headers }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: ThemeColor.contentBarColor))
    }

    @ViewBuilder
    private var content: some View {
        if sender.isSending(draftId: draft.id) {
            HStack {
                Spacer()
                ProgressView().controlSize(.small)
                Text("Sending…".localized)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxHeight: .infinity)
        } else if let err = draft.lastRun?.error {
            errorView(err)
        } else if draft.lastRun == nil {
            emptyState
        } else {
            switch selectedTab {
            case .body: bodyView
            case .headers: headersView
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "paperplane")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(.secondary)
            Text("Press Send to dispatch this request.".localized)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Request failed.".localized)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.red)
            Text(message)
                .font(.system(size: 11).monospaced())
                .textSelection(.enabled)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
    }

    @ViewBuilder
    private var bodyView: some View {
        if let data = responseBodyData() {
            let representation = DataRepresentationParser.parse(data: data, contentType: responseContentType())
            VStack(spacing: 0) {
                if let representation = representation {
                    representationView(representation)
                } else {
                    Spacer()
                    Text("No Data".localized)
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                    Spacer()
                }
                bodyActionBar(representation: representation, data: data)
            }
        } else {
            VStack {
                Spacer()
                Text("No Data".localized)
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func representationView(_ representation: DataRepresentation) -> some View {
        switch representation.type ?? .text {
        case .image:
            if let imageRep = representation as? DataImageRepresentation, let image = imageRep.image {
                ImageContentView(image: image)
            } else {
                ImageContentView(data: representation.originalData)
            }
        case .json:
            if jsonRaw {
                CodeTextView(text: representation.rawString ?? "")
            } else {
                JSONWebView(jsonString: representation.rawString ?? "")
            }
        case .binary:
            VStack {
                Spacer()
                Image(systemName: "doc.zipper")
                    .font(.system(size: 30))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 6)
                Text("Binary Data".localized)
                    .font(.system(size: 13, weight: .semibold))
                Text(String(format: "Size: %@".localized,
                            OverviewRepresentation.formatBytes(representation.originalData?.count ?? 0)))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
            }
        case .text:
            CodeTextView(text: representation.rawString ?? "")
        }
    }

    private func bodyActionBar(representation: DataRepresentation?, data: Data) -> some View {
        HStack(spacing: 8) {
            if let imageRep = representation as? DataImageRepresentation,
               let image = imageRep.image {
                Text("\(Int(image.size.width))×\(Int(image.size.height)) • \(OverviewRepresentation.formatBytes(data.count))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            } else {
                Text(OverviewRepresentation.formatBytes(data.count))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if representation?.type == .json {
                DetailActionButton(title: "Raw".localized,
                                   iconName: "text.quote.rtl",
                                   isSelected: jsonRaw) {
                    jsonRaw.toggle()
                }
            }
            DetailActionButton(title: "Copy".localized, iconName: "doc.on.doc") {
                copyResponseBody(representation: representation, data: data)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: ThemeColor.contentBarColor))
    }

    private func responseBodyData() -> Data? {
        guard let b64 = draft.lastRun?.responseBodyBase64,
              let data = Data(base64Encoded: b64),
              !data.isEmpty else { return nil }
        return data
    }

    private func responseContentType() -> String? {
        let headers = draft.lastRun?.responseHeaders ?? [:]
        return headers.first(where: { $0.key.caseInsensitiveCompare("content-type") == .orderedSame })?.value
    }

    private func copyResponseBody(representation: DataRepresentation?, data: Data) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let imageRep = representation as? DataImageRepresentation, let image = imageRep.image {
            pb.writeObjects([image])
            return
        }
        if let raw = representation?.rawString, !raw.isEmpty {
            pb.setString(raw, forType: .string)
            return
        }
        if let s = String(data: data, encoding: .utf8) {
            pb.setString(s, forType: .string)
        } else {
            pb.setData(data, forType: .fileContents)
        }
    }

    private var headersView: some View {
        let entries = (draft.lastRun?.responseHeaders ?? [:])
            .sorted(by: { $0.key < $1.key })
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(entries, id: \.key) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Text(entry.key)
                            .font(.system(size: 11, weight: .medium).monospaced())
                            .frame(width: 180, alignment: .leading)
                        Text(entry.value)
                            .font(.system(size: 11).monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }
    }

    private func statusBadge(_ code: Int) -> some View {
        Text("\(code)")
            .font(.system(size: 10, weight: .semibold).monospaced())
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color(for: code))
            .cornerRadius(3)
    }

    private func color(for code: Int) -> Color {
        switch code {
        case 200..<300: return .statusGreen
        case 300..<400: return .statusOrange
        case 400..<600: return .statusRed
        default: return .secondary
        }
    }
}
