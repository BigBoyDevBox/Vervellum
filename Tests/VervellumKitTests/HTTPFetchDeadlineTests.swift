import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(VervellumKit)
@testable import VervellumKit
#else
@testable import Vervellum
#endif

private enum HTTPStatus {
    static let ok = 200
    static let found = 302
}

private let rescueDelay: TimeInterval = 2

final class HTTPFetchDeadlineTests: XCTestCase {
    func testDeadlineIncludesWaitingForHeaders() async throws {
        try await assertDeadline(path: "headers")
    }

    func testDeadlineInterruptsAStalledBody() async throws {
        try await assertDeadline(path: "body")
    }

    func testFastPageReturnsItsResponseAndBody() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StalledPageProtocol.self]
        let transport = HTTPTransport(configuration: configuration)
        let request = HTTPTransport.getRequest(url: try XCTUnwrap(URL(string: "https://page.example/success")))
        let (response, data) = try await transport.fetch(request, limit: 1024, deadline: 2)
        XCTAssertEqual(response.statusCode, HTTPStatus.ok)
        XCTAssertEqual(String(data: data, encoding: .utf8), "partial")
    }

    func testCancellationBeforeHeadersDoesNotWaitForTheDeadline() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StalledPageProtocol.self]
        let transport = HTTPTransport(configuration: configuration)
        let request = HTTPTransport.getRequest(url: try XCTUnwrap(URL(string: "https://page.example/headers")))
        let started = ProcessInfo.processInfo.systemUptime
        defer { XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, rescueDelay / 2) }
        let task = Task { try await transport.fetch(request, limit: 1024, deadline: rescueDelay) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled fetch must fail")
        } catch {
            XCTAssertEqual(error as? ResearchError, .cancelled)
        }
    }

    func testRedirectHopsShareThePageBudget() async {
        let transport = StubTransport { call in
            if call.url.path == "/start" {
                return .page(status: HTTPStatus.found, headers: ["Location": "/end"], text: "")
            }
            return .page(status: HTTPStatus.ok, headers: [:], text: String(repeating: "Page text. ", count: 40))
        }
        let reader = DirectPageReader(trace: ResearchTrace(sink: SilentLog()), transport: transport)
        let pages = await reader.read([
            Source(number: 1, url: "https://page.example/start", title: "Page", snippet: ""),
        ])
        XCTAssertFalse(pages.isEmpty)
        XCTAssertEqual(transport.calls.count, 2)
        for call in transport.calls {
            XCTAssertGreaterThan(call.deadline ?? 0, 0)
            XCTAssertLessThanOrEqual(call.deadline ?? .infinity, DirectPageReader.perPageTimeout)
            XCTAssertEqual(call.timeout, call.deadline)
        }
        XCTAssertLessThanOrEqual(transport.calls.last?.deadline ?? .infinity,
                                 transport.calls.first?.deadline ?? 0)
    }

    private func assertDeadline(path: String) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StalledPageProtocol.self]
        let transport = HTTPTransport(configuration: configuration)
        let request = HTTPTransport.getRequest(url: try XCTUnwrap(URL(string: "https://page.example/" + path)))
        let budget: TimeInterval = 0.02
        let started = ProcessInfo.processInfo.systemUptime
        defer { XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, rescueDelay / 2) }
        do {
            _ = try await transport.fetch(request, limit: 1024, deadline: budget)
            XCTFail("A stalled exchange must expire")
        } catch {
            XCTAssertEqual(error as? ResearchError, HTTPTransport.tookTooLong(budget))
        }
    }
}

private final class StalledPageProtocol: URLProtocol {
    private let lock = NSLock()
    private var rescue: DispatchWorkItem?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // A distinct fallback error makes a missing deadline fail instead of hanging CI.
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
        }
        lock.lock()
        rescue = work
        lock.unlock()
        if request.url?.path != "/headers", let url = request.url,
           let response = HTTPURLResponse(url: url, statusCode: HTTPStatus.ok,
                                          httpVersion: "HTTP/1.1", headerFields: nil) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("partial".utf8))
            if request.url?.path == "/success" {
                client?.urlProtocolDidFinishLoading(self)
                return
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + rescueDelay, execute: work)
    }

    override func stopLoading() {
        lock.lock()
        let work = rescue
        rescue = nil
        lock.unlock()
        work?.cancel()
    }
}
