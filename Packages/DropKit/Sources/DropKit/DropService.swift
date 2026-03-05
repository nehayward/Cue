import Foundation

/// A service for creating and retrieving short-lived code-based data transfers.
public enum DropService {
    private static let baseURL = "https://api.clic.dance/drop"

    /// Creates a drop with the given value and returns a code.
    /// - Parameters:
    ///   - value: The value to store (e.g., Sonos IP address)
    ///   - ttl: Time to live in seconds (default 120)
    /// - Returns: DropResponse containing the code, ttl, and image URL
    public static func drop(value: String, ttl: Int = 120) async throws -> DropResponse {
        guard let url = URL(string: baseURL) else {
            throw DropError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(DropRequest(value: value, ttl: ttl))
        } catch {
            throw DropError.decodingError(error.localizedDescription)
        }

        return try await perform(request)
    }

    /// Picks up a value using the provided code.
    /// - Parameter code: The 6-character code
    /// - Returns: The stored value (e.g., Sonos IP address)
    public static func pickup(code: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/\(code.uppercased())") else {
            throw DropError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let response: PickupResponse = try await perform(request)

        if let error = response.error {
            throw error.lowercased().contains("expired") ? DropError.codeExpired : DropError.serverError(error)
        }

        guard let value = response.value else {
            throw DropError.invalidResponse
        }

        return value
    }

    private static func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw DropError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DropError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            throw DropError.codeNotFound
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(PickupResponse.self, from: data),
               let error = errorResponse.error {
                throw DropError.serverError(error)
            }
            throw DropError.serverError("Server returned status \(httpResponse.statusCode)")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw DropError.decodingError(error.localizedDescription)
        }
    }
}

private struct DropRequest: Encodable, Sendable {
    let value: String
    let ttl: Int
}
