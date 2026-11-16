import ColibriKit
import Foundation

extension URLSession {
    /// A short-timeout session for talking to servers on this Mac.
    public static let kolibrie: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()
}

/// What `GET /health` returns from a Colibri server.
public struct Health: Sendable, Equatable, Decodable {
    public var status: String
    public var arch: String?
    public var isOK: Bool { status == "ok" }
}

/// A model a server lists at `/v1/models`.
public struct RemoteModel: Sendable, Equatable, Identifiable {
    public var id: String
    public var raw: [String: JSONValue]

    /// The context length, under whichever key the server uses.
    public var contextLength: Int? {
        for key in ["context_length", "context_window", "max_context_length", "max_model_len"] {
            if case .number(let value)? = raw[key] { return Int(value) }
        }
        return nil
    }
}

public enum ProbeError: Error, LocalizedError, Equatable {
    case badStatus(Int)
    case unreadable

    public var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "The server answered with HTTP \(code)."
        case .unreadable: return "The server's answer could not be read."
        }
    }
}

/// Talks to one running Colibri server.
public struct ServerProbe: Sendable {
    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .kolibrie) {
        self.baseURL = baseURL
        self.session = session
    }

    /// The server's health, or nil if nothing answers on that port.
    public func health() async -> Health? {
        guard let (data, response) = try? await session.data(from: baseURL.appendingPathComponent("health")),
            (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return try? JSONDecoder().decode(Health.self, from: data)
    }

    public func models() async throws -> [RemoteModel] {
        struct List: Decodable { var data: [[String: JSONValue]] }
        let (data, response) = try await session.data(from: baseURL.appendingPathComponent("v1/models"))
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ProbeError.badStatus(code) }
        guard let list = try? JSONDecoder().decode(List.self, from: data) else { throw ProbeError.unreadable }
        return list.data.compactMap { entry in
            guard case .string(let id)? = entry["id"] else { return nil }
            return RemoteModel(id: id, raw: entry)
        }
    }
}
