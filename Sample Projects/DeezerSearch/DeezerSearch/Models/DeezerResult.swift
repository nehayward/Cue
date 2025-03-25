//
//  DeezerResult.swift
//  DeezerSearch
//
//  Created by Nick Hayward on 8/25/24.
//
import Foundation

struct DeezerResult: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let album: DeezerAlbum
    
    struct DeezerAlbum: Codable, Identifiable, Hashable {
        let id: Int
        let cover: URL?
    }
}
