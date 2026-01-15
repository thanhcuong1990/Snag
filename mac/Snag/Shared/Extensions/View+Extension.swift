import SwiftUI

extension View {
    /// Applies a modifier to a view conditionally.
    ///
    /// - Parameters:
    ///   - condition: The condition to determine if the modifier should be applied.
    ///   - modifier: The modifier to apply to the view.
    /// - Returns: The modified view or the original view.
    @ViewBuilder
    func modify<Content: View>(@ViewBuilder _ modifier: (Self) -> Content) -> Content {
        modifier(self)
    }
}
