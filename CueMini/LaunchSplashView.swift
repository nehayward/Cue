import SwiftUI

struct LaunchSplashView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            
            Text("Cue Mini is Active")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Check your menu bar")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(width: 280)
        .onAppear {
            // Auto-close after 1.5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }
        }
    }
}

#Preview {
    LaunchSplashView()
}


