import Foundation
import XCTest
@testable import YouthAISubsidy

final class SpreadsheetURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> Data)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let data = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class SpreadsheetTransportTests: XCTestCase {
    private let url = URL(string: "https://script.google.com/macros/s/test-only/exec")!

    override func tearDown() {
        SpreadsheetURLProtocol.handler = nil
        super.tearDown()
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SpreadsheetURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func bodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            if count == 0 { break }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result
    }

    func testSubmitSendsFormToFixedSpreadsheetEndpoint() async throws {
        var draft = SubsidyCase.blank(caseId: "DRAFT-TEST-1")
        draft.applicant.fullName = "測試申請人"
        SpreadsheetURLProtocol.handler = { [url] request in
            XCTAssertEqual(request.url, url)
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try self.bodyData(from: request)
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(payload["action"] as? String, "submit")
            XCTAssertEqual(payload["clientKey"] as? String, "test-only-key")
            XCTAssertEqual(payload["clientSubmissionId"] as? String, draft.caseId)
            XCTAssertEqual((payload["applicant"] as? [String: Any])?["fullName"] as? String, "測試申請人")
            return Data("{\"ok\":true,\"case\":{\"caseId\":\"MZT-TEST\",\"status\":\"submitted\"},\"accessToken\":\"test-token\"}".utf8)
        }
        let receipt = try await MobileSubmissionClient.submit(
            draft, baseURL: url, clientKey: "test-only-key", session: session()
        )
        XCTAssertEqual(receipt.case.caseId, "MZT-TEST")
        XCTAssertEqual(receipt.accessToken, "test-token")
    }

    func testStatusReadsHumanDecisionWithoutURLQueryToken() async throws {
        SpreadsheetURLProtocol.handler = { [url] request in
            XCTAssertEqual(request.url, url)
            XCTAssertNil(request.url?.query)
            let body = try self.bodyData(from: request)
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(payload["action"] as? String, "status")
            XCTAssertEqual(payload["accessToken"] as? String, "test-token")
            return Data("{\"ok\":true,\"caseId\":\"MZT-TEST\",\"status\":\"approved\",\"statusNote\":\"已完成審查\"}".utf8)
        }
        let status = try await MobileSubmissionClient.status(
            caseId: "MZT-TEST", accessToken: "test-token",
            baseURL: url, clientKey: "test-only-key", session: session()
        )
        XCTAssertEqual(status.status, .approved)
        XCTAssertEqual(status.statusNote, "已完成審查")
    }

    func testServiceErrorNeverAppearsAsSuccessfulSubmission() async throws {
        SpreadsheetURLProtocol.handler = { _ in
            Data("{\"ok\":false,\"error\":\"試算表標題不一致\"}".utf8)
        }
        do {
            _ = try await MobileSubmissionClient.submit(
                .blank(), baseURL: url, clientKey: "test-only-key", session: session()
            )
            XCTFail("收件失敗不可顯示為已送達")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("試算表標題不一致"))
        }
    }
}
