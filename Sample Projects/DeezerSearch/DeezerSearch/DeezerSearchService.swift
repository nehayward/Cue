//
//  DeezerSearchService.swift
//  DeezerSearch
//
//  Created by Nick Hayward on 8/25/24.
//
import Foundation

final class DeezerSearchService {
    private let session: URLSession
    private let decoder: JSONDecoder
    
    init(session: URLSession = .shared, decoder: JSONDecoder = JSONDecoder()) {
        self.session = session
        self.decoder = decoder
    }
    
    func search(for query: String) async throws -> [DeezerResult] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.deezer.com"
        components.path = "/search"
        components.queryItems = [.init(name: "q", value: query)]
        
        guard let url = components.url else {
            throw DeezerError.construction("")
        }
        
        let request = URLRequest(url: url)
        
        let (data, response) = try await session.data(for: request)
        
        print(String(decoding: data, as: UTF8.self))
        
        let result = try decoder.decode(DeezerContainer.self, from: data)
        return result.data
    }
}

struct DeezerContainer: Codable {
    let data: [DeezerResult]
}
