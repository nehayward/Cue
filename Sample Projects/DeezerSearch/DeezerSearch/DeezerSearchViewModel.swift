//
//  DeezerSearchViewModel.swift
//  DeezerSearch
//
//  Created by Nick Hayward on 8/25/24.
//
import Observation
import Foundation

@Observable
final class DeezerSearchViewModel {
    var errorMessage: String?
    var query: String = ""
    var results: [DeezerResult] = []
    private let deezerSearchService: DeezerSearchService
    private var searchTask: Task<Void,Error>?
    
    init(deezerSearchService: DeezerSearchService) {
        self.deezerSearchService = deezerSearchService
    }
    
    func search(for query: String) {
        guard !query.isEmpty else { return }
        
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for:.milliseconds(1000))
            do {
                results = try await deezerSearchService.search(for: query)
            } catch URLError.cancelled {
                print("Cancelled")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}


