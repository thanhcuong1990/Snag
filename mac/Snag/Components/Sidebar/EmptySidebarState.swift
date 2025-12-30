import SwiftUI

struct EmptySidebarState: View {
    @State private var isPulsing = false
    
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 40)
            
            ZStack {
                Circle()
                    .stroke(Color.secondaryLabelColor.opacity(0.2), lineWidth: 1)
                    .frame(width: 50, height: 50)
                    .scaleEffect(isPulsing ? 1.2 : 1.0)
                    .opacity(isPulsing ? 0 : 1)
                
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 20))
                    .foregroundColor(.secondaryLabelColor.opacity(0.5))
            }
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    isPulsing = true
                }
            }
            
            VStack(spacing: 6) {
                Text("No Apps Connected")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondaryLabelColor)
                
                Text("Waiting for devices on port \(String(SnagConfiguration.netServicePort))...")
                    .font(.system(size: 10))
                    .foregroundColor(.secondaryLabelColor.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
    }
}
