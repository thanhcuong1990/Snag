import SwiftUI

/// Vertical list of available `ExportFormat`s. Clicking a row selects it.
/// The selected row uses the system selected-control color to match the rest
/// of Snag's lists.
struct CodeFormatSidebar: View {
    @Binding var selection: ExportFormat
    var formats: [ExportFormat] = ExportFormat.allCases

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(formats) { format in
                    row(format)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 180)
        .background(Color(nsColor: ThemeColor.contentBarColor))
    }

    @ViewBuilder
    private func row(_ format: ExportFormat) -> some View {
        let isSelected = format == selection
        Button(action: { selection = format }) {
            HStack {
                Text(format.displayName)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .primary : .secondary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected
                    ? Color(nsColor: .selectedControlColor).opacity(0.4)
                    : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}
