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

    func testFirstRequestHasNoConditionalHeaderAndSkipsURLCache() {
        let cache = ConditionalResponseCache()

        let prepared = cache.prepare(URLRequest(url: url))

        XCTAssertNil(prepared.value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertEqual(prepared.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testSendsStoredETagOnNextRequest() {
        let cache = ConditionalResponseCache()
        let request = URLRequest(url: url)
        _ = cache.resolve(cache.prepare(request), data: Data("body".utf8), response: response(200, etag: "W/\"abc\""))

        let prepared = cache.prepare(request)

        XCTAssertEqual(prepared.value(forHTTPHeaderField: "If-None-Match"), "W/\"abc\"")
    }

    func testNotModifiedReturnsCachedBodyAsOK() {
        let cache = ConditionalResponseCache()
        let request = URLRequest(url: url)
        _ = cache.resolve(cache.prepare(request), data: Data("body".utf8), response: response(200, etag: "\"abc\""))

        let (data, statusCode) = cache.resolve(cache.prepare(request), data: Data(), response: response(304))

        XCTAssertEqual(statusCode, 200)
        XCTAssertEqual(data, Data("body".utf8))
    }

    func testNotModifiedWithoutStoredBodyPassesThrough() {
        let cache = ConditionalResponseCache()

        let (data, statusCode) = cache.resolve(URLRequest(url: url), data: Data(), response: response(304))

        XCTAssertEqual(statusCode, 304)
        XCTAssertTrue(data.isEmpty)
    }

    func testDoesNotStoreResponsesWithoutETagOrWithErrors() {
        let cache = ConditionalResponseCache()
        let request = URLRequest(url: url)
        _ = cache.resolve(request, data: Data("body".utf8), response: response(200))
        _ = cache.resolve(request, data: Data("limit".utf8), response: response(403, etag: "\"abc\""))

        XCTAssertNil(cache.prepare(request).value(forHTTPHeaderField: "If-None-Match"))
    }

    func testIgnoresNonGetRequests() {
        let cache = ConditionalResponseCache()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        _ = cache.resolve(request, data: Data("body".utf8), response: response(200, etag: "\"abc\""))

        XCTAssertNil(cache.prepare(URLRequest(url: url)).value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertNil(cache.prepare(request).value(forHTTPHeaderField: "If-None-Match"))
    }

    func testRemoveAllForgetsStoredETags() {
        let cache = ConditionalResponseCache()
        let request = URLRequest(url: url)
        _ = cache.resolve(request, data: Data("body".utf8), response: response(200, etag: "\"abc\""))

        cache.removeAll()

        XCTAssertNil(cache.prepare(request).value(forHTTPHeaderField: "If-None-Match"))
    }
}
