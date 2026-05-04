import SwiftUI

struct DraftEditorView: View {
    @ObservedObject var draft: RequestDraft
    @State private var editorTab: EditorTab = .params
    @State private var splitRatio: CGFloat = 0.55
    @State private var isDragging: Bool = false

    enum EditorTab: Hashable { case params, headers, body, code }

    var body: some View {
        VStack(spacing: 0) {
            RequestBar(draft: draft, onSend: send)
            Divider()

            GeometryReader { geo in
                let topHeight = max(120, geo.size.height * splitRatio)
                let bottomHeight = max(120, geo.size.height - topHeight - 1)

                VStack(spacing: 0) {
                    editorPane
                        .frame(height: topHeight)

                    ResizableDivider(isDragging: $isDragging, orientation: .vertical)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    isDragging = true
                                    let total = geo.size.height
                                    guard total > 0 else { return }
                                    let next = (topHeight + value.translation.height) / total
                                    splitRatio = min(0.85, max(0.15, next))
                                }
                                .onEnded { _ in isDragging = false }
                        )

                    DraftResponseView(draft: draft)
                        .frame(height: bottomHeight)
                }
            }
        }
        .background(Color(nsColor: ThemeColor.controlBackgroundColor))
    }

    private var editorPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TabButton(title: "Params".localized,
                          isSelected: editorTab == .params) { editorTab = .params }
                TabButton(title: "Headers".localized,
                          isSelected: editorTab == .headers) { editorTab = .headers }
                TabButton(title: "Body".localized,
                          isSelected: editorTab == .body) { editorTab = .body }
                TabButton(title: "Code".localized,
                          isSelected: editorTab == .code) { editorTab = .code }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(nsColor: ThemeColor.contentBarColor))

            Divider()

            switch editorTab {
            case .params:
                EditableKeyValueListView(
                    draft: draft,
                    keyPath: \.queryParams,
                    onURLRebuildNeeded: true
                )
            case .headers:
                EditableKeyValueListView(
                    draft: draft,
                    keyPath: \.headers,
                    onURLRebuildNeeded: false
                )
            case .body:
                BodyEditorView(draft: draft)
            case .code:
                DraftCodeView(draft: draft)
            }
        }
    }

    private func send() {
        RequestSender.shared.send(draft)
    }
}
