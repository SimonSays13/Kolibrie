import ColibriKit
import Foundation
import Testing
import os

@testable import ColibriAPI

/// Answers requests from a table instead of the network. Each test uses its own port.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    static let responses = OSAllocatedUnfairLock(initialState: [String: (status: Int, body: Data)]())

    static func register(_ url: String, status: Int = 200, body: String) {
        responses.withLock { $0[url] = (status, Data(body.utf8)) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let key = request.url?.absoluteString ?? ""
        guard let entry = Self.responses.withLock({ $0[key] }), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: entry.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: entry.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Server probe")
struct ServerProbeTests {
    func probe(port: Int) -> ServerProbe {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return ServerProbe(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!, session: URLSession(configuration: configuration))
    }

    @Test func healthyServer() async {
        MockURLProtocol.register("http://127.0.0.1:18001/health", body: #"{"status":"ok","arch":"qwen36"}"#)
        let health = await probe(port: 18001).health()
        #expect(health?.isOK == true)
        #expect(health?.arch == "qwen36")
    }

    @Test func nothingListening() async {
        #expect(await probe(port: 18002).health() == nil)
    }

    @Test func serverErrorIsNotHealthy() async {
        MockURLProtocol.register("http://127.0.0.1:18003/health", status: 500, body: "{}")
        #expect(await probe(port: 18003).health() == nil)
    }

    @Test func listsModelsWithContextLength() async throws {
        MockURLProtocol.register(
            "http://127.0.0.1:18004/v1/models",
            body: #"{"object":"list","data":[{"id":"qwen3.6-colibri","context_length":131072}]}"#)
        let models = try await probe(port: 18004).models()
        #expect(models.map(\.id) == ["qwen3.6-colibri"])
        #expect(models.first?.contextLength == 131072)
    }

    @Test func modelListFromARealServer() async throws {
        // Captured from Colibri 2.1.0 serving Qwen3.6-35B-A3B.
        MockURLProtocol.register(
            "http://127.0.0.1:18006/v1/models",
            body:
                #"{"object":"list","data":[{"id":"qwen3.6-colibri","object":"model","created":1794855574,"owned_by":"colibri","input_modalities":["text"],"capabilities":["chat","systemone"],"context_length":131072,"max_model_len":131072}],"models":[{"name":"qwen3.6-colibri","release_date":"2026-11-16"}]}"#
        )
        let model = try #require(try await probe(port: 18006).models().first)
        #expect(model.id == "qwen3.6-colibri")
        #expect(model.contextLength == 131072)
    }

    @Test func badStatusFromModelList() async {
        MockURLProtocol.register("http://127.0.0.1:18005/v1/models", status: 404, body: "")
        await #expect(throws: ProbeError.badStatus(404)) { try await probe(port: 18005).models() }
    }
}
