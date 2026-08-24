import SwiftUI

struct ReleaseNotesView: View {
    @State private var releaseNotes: LocalizedStringKey = "Loading..."
    
    var body: some View {
        ScrollView {
            Text(releaseNotes)
                .padding()
        }
        .navigationTitle("Release Notes")
        .onAppear(perform: fetchReleaseNotes)
    }
    
    @MainActor
    private func fetchReleaseNotes() {
        Task {
            guard let url = URL(string: "https://resource.clic.dance/ReleaseNotes.md") else {
                await MainActor.run {
                    releaseNotes = "Invalid URL"
                }
                return
            }
            
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let notes = String(data: data, encoding: .utf8) else {
                    
                    releaseNotes = "Failed to load data"
                    return
                }
                releaseNotes = LocalizedStringKey(notes)
            } catch {
                releaseNotes = LocalizedStringKey("Failed to load: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    NavigationView {
        ReleaseNotesView()
    }
}
