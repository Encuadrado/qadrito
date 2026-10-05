import XCTest
@testable import QAdrito

final class ConditionalResponseCacheTests: XCTestCase {
    private let url = URL(string: "https://api.github.com/repos/Encuadrado/qadrito/pulls/1")!

    private func response(_ statusCode: Int, etag: String? = nil) -> HTTPURLResponse {
        var headers: [String: String] = [:]
        if let etag {
            headers["ETag"] = etag
        }
        return HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    private func store(_ cache: ConditionalResponseCache, body: String, etag: String) {
        _ = cache.resolve(cache.prepare(URLRequest(url: url)), data: Data(body.utf8), response: response(200, etag: etag))
    }

    func testFirstRequestHasNoConditionalHeaderAndSkipsURLCache() {
        let cache = ConditionalResponseCache()

        let prepared = cache.prepare(URLRequest(url: url)).request

        XCTAssertNil(prepared.value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertEqual(prepared.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testSendsStoredETagOnNextRequest() {
        let cache = ConditionalResponseCache()
        store(cache, body: "body", etag: "W/\"abc\"")

        let prepared = cache.prepare(URLRequest(url: url)).request

        XCTAssertEqual(prepared.value(forHTTPHeaderField: "If-None-Match"), "W/\"abc\"")
    }

    func testNotModifiedReturnsCachedBodyAsOK() {
        let cache = ConditionalResponseCache()
        store(cache, body: "body", etag: "\"abc\"")

        let (data, statusCode) = cache.resolve(cache.prepare(URLRequest(url: url)), data: Data(), response: response(304))

        XCTAssertEqual(statusCode, 200)
        XCTAssertEqual(data, Data("body".utf8))
    }

    func testNotModifiedUsesTheEntryWhoseETagWasSent() {
        let cache = ConditionalResponseCache()
        store(cache, body: "first", etag: "\"one\"")
        let inFlight = cache.prepare(URLRequest(url: url))
        store(cache, body: "second", etag: "\"two\"")

        let (data, statusCode) = cache.resolve(inFlight, data: Data(), response: response(304))

        XCTAssertEqual(inFlight.request.value(forHTTPHeaderField: "If-None-Match"), "\"one\"")
        XCTAssertEqual(statusCode, 200)
        XCTAssertEqual(data, Data("first".utf8))
    }

    func testNotModifiedWithoutStoredBodyPassesThrough() {
        let cache = ConditionalResponseCache()

        let (data, statusCode) = cache.resolve(cache.prepare(URLRequest(url: url)), data: Data(), response: response(304))

        XCTAssertEqual(statusCode, 304)
        XCTAssertTrue(data.isEmpty)
    }

    func testDoesNotStoreResponsesWithoutETagOrWithErrors() {
        let cache = ConditionalResponseCache()
        _ = cache.resolve(cache.prepare(URLRequest(url: url)), data: Data("body".utf8), response: response(200))
        _ = cache.resolve(cache.prepare(URLRequest(url: url)), data: Data("limit".utf8), response: response(403, etag: "\"abc\""))

        XCTAssertNil(cache.prepare(URLRequest(url: url)).request.value(forHTTPHeaderField: "If-None-Match"))
    }

    func testIgnoresNonGetRequests() {
        let cache = ConditionalResponseCache()
        var post = URLRequest(url: url)
        post.httpMethod = "POST"
        _ = cache.resolve(cache.prepare(post), data: Data("body".utf8), response: response(200, etag: "\"abc\""))

        XCTAssertNil(cache.prepare(URLRequest(url: url)).request.value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertNil(cache.prepare(post).request.value(forHTTPHeaderField: "If-None-Match"))
    }

    func testRemoveAllForgetsStoredETags() {
        let cache = ConditionalResponseCache()
        store(cache, body: "body", etag: "\"abc\"")

        cache.removeAll()

        XCTAssertNil(cache.prepare(URLRequest(url: url)).request.value(forHTTPHeaderField: "If-None-Match"))
    }

    func testNotModifiedAfterRemoveAllDoesNotReplayTheOldBody() {
        let cache = ConditionalResponseCache()
        store(cache, body: "old account", etag: "\"abc\"")
        let inFlight = cache.prepare(URLRequest(url: url))

        cache.removeAll()
        let (data, statusCode) = cache.resolve(inFlight, data: Data(), response: response(304))

        XCTAssertEqual(statusCode, 304)
        XCTAssertTrue(data.isEmpty)
    }

    func testRequestStartedBeforeRemoveAllCannotStoreItsResponse() {
        let cache = ConditionalResponseCache()
        let inFlight = cache.prepare(URLRequest(url: url))

        cache.removeAll()
        _ = cache.resolve(inFlight, data: Data("old account".utf8), response: response(200, etag: "\"abc\""))

        XCTAssertNil(cache.prepare(URLRequest(url: url)).request.value(forHTTPHeaderField: "If-None-Match"))
    }
}
