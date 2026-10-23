import XCTest

/// Every request goes through `PolarStubURLProtocol`, which answers the way
/// Polar's customer portal endpoints do, so nothing reaches the network.
final class LicenseClientTests: XCTestCase {
    private static let config = LicenseConfig(
        apiBase: URL(string: "https://polar.test")!,
        organizationID: "1dbfc517-0bbf-4301-9ba8-555ca42b9737",
        checkoutURL: URL(string: "https://polar.test/checkout")!,
        customerPortalURL: URL(string: "https://polar.test/portal")!
    )
    private static let key = "AGENTCAF-3F2C1D0E-8B7A-4C6D-9E5F-1A2B3C4D5E6F"
    private static let activationID = "a1b2c3d4-0000-4000-8000-000000000001"

    private var client: LicenseClient!

    override func setUp() {
        super.setUp()
        PolarStubURLProtocol.reset()
        client = LicenseClient(config: Self.config, session: PolarStubURLProtocol.session())
    }

    override func tearDown() {
        PolarStubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: Config

    func testDebugBuildUsesSandbox() {
        XCTAssertEqual(LicenseConfig.current, .sandbox)
        XCTAssertEqual(LicenseConfig.sandbox.apiBase.host, "sandbox-api.polar.sh")
        XCTAssertEqual(LicenseConfig.production.apiBase.host, "api.polar.sh")
        XCTAssertNotNil(UUID(uuidString: LicenseConfig.production.organizationID))
        XCTAssertNotNil(UUID(uuidString: LicenseConfig.sandbox.organizationID))
    }

    // MARK: Requests

    func testActivateRequest() async throws {
        PolarStubURLProtocol.answerWith(Self.activated())
        _ = await client.activate(key: "  \(Self.key)\n", label: "MacBookPro18,3")

        let request = try XCTUnwrap(PolarStubURLProtocol.requests.last)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://polar.test/v1/customer-portal/license-keys/activate")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(PolarStubURLProtocol.lastBody())
        XCTAssertEqual(Set(body.keys), ["key", "organization_id", "label", "meta"])
        XCTAssertEqual(body["key"] as? String, Self.key)
        XCTAssertEqual(body["organization_id"] as? String, Self.config.organizationID)
        XCTAssertEqual(body["label"] as? String, "MacBookPro18,3")
        XCTAssertEqual((body["meta"] as? [String: Any])?.isEmpty, true)
    }

    func testValidateAlwaysSendsTheActivationID() async throws {
        PolarStubURLProtocol.answerWith(Self.validated(status: "granted", activationID: Self.activationID))
        _ = await client.validate(key: "\t\(Self.key) ", activationID: Self.activationID)

        let request = try XCTUnwrap(PolarStubURLProtocol.requests.last)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v1/customer-portal/license-keys/validate")
        let body = try XCTUnwrap(PolarStubURLProtocol.lastBody())
        XCTAssertEqual(Set(body.keys), ["key", "organization_id", "activation_id"])
        XCTAssertEqual(body["key"] as? String, Self.key)
        XCTAssertEqual(body["activation_id"] as? String, Self.activationID)
    }

    func testValidateWithoutAnActivationAsksNothing() async {
        let result = await client.validate(key: Self.key, activationID: "")
        XCTAssertEqual(result, .notFound)
        XCTAssertTrue(PolarStubURLProtocol.requests.isEmpty)
    }

    func testDeactivateRequest() async throws {
        PolarStubURLProtocol.answerWith("", status: 204)
        let result = await client.deactivate(key: Self.key, activationID: Self.activationID)
        XCTAssertEqual(result, .deactivated)

        let request = try XCTUnwrap(PolarStubURLProtocol.requests.last)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v1/customer-portal/license-keys/deactivate")
        let body = try XCTUnwrap(PolarStubURLProtocol.lastBody())
        XCTAssertEqual(Set(body.keys), ["key", "organization_id", "activation_id"])
        XCTAssertEqual(body["activation_id"] as? String, Self.activationID)
    }

    func testBlankKeyAsksNothing() async {
        let activation = await client.activate(key: " \n", label: "Mac")
        XCTAssertEqual(activation, .notFound)
        XCTAssertTrue(PolarStubURLProtocol.requests.isEmpty)
    }

    // MARK: Activate answers

    func testActivateAnswers() async {
        PolarStubURLProtocol.answerWith(Self.activated())
        var result = await client.activate(key: Self.key, label: "Mac")
        XCTAssertEqual(result, .activated(id: Self.activationID, macs: 1))

        PolarStubURLProtocol.answerWith(#"{"error":"NotPermitted","detail":"License key activation limit already reached"}"#, status: 403)
        result = await client.activate(key: Self.key, label: "Mac")
        XCTAssertEqual(result, .limitReached)

        PolarStubURLProtocol.answerWith(#"{"error":"ResourceNotFound","detail":"Not found"}"#, status: 404)
        result = await client.activate(key: Self.key, label: "Mac")
        XCTAssertEqual(result, .notFound)

        PolarStubURLProtocol.answerWith(#"{"error":"ResourceNotFound","detail":"License key is no longer active."}"#, status: 404)
        result = await client.activate(key: Self.key, label: "Mac")
        XCTAssertEqual(result, .revoked)

        PolarStubURLProtocol.answerWith(Self.activated(status: "revoked"))
        result = await client.activate(key: Self.key, label: "Mac")
        XCTAssertEqual(result, .revoked)
    }

    func testActivateCouldNotAsk() async {
        for status in [429, 500, 503, 422] {
            PolarStubURLProtocol.answerWith("", status: status)
            let result = await client.activate(key: Self.key, label: "Mac")
            XCTAssertEqual(result, .unavailable, "\(status)")
        }
        PolarStubURLProtocol.failWith(URLError(.timedOut))
        let result = await client.activate(key: Self.key, label: "Mac")
        XCTAssertEqual(result, .unavailable)
    }

    // MARK: Validate answers

    func testValidateAnswers() async {
        PolarStubURLProtocol.answerWith(Self.validated(status: "granted", activationID: Self.activationID))
        var result = await client.validate(key: Self.key, activationID: Self.activationID)
        XCTAssertEqual(result, .valid)

        for status in ["revoked", "disabled"] {
            PolarStubURLProtocol.answerWith(Self.validated(status: status, activationID: Self.activationID))
            result = await client.validate(key: Self.key, activationID: Self.activationID)
            XCTAssertEqual(result, .revoked, status)
        }

        // The activation was freed elsewhere, or the key is unknown.
        PolarStubURLProtocol.answerWith(#"{"error":"ResourceNotFound","detail":"Not found"}"#, status: 404)
        result = await client.validate(key: Self.key, activationID: Self.activationID)
        XCTAssertEqual(result, .notFound)
    }

    func testValidateAboutAnotherActivationIsNoProof() async {
        // Neither proof nor a sign the activation is gone: a granted answer
        // that lost the field must not cost every paying Mac its license.
        PolarStubURLProtocol.answerWith(Self.validated(status: "granted", activationID: nil))
        var result = await client.validate(key: Self.key, activationID: Self.activationID)
        XCTAssertEqual(result, .unavailable)

        PolarStubURLProtocol.answerWith(Self.validated(status: "granted", activationID: "someone-else"))
        result = await client.validate(key: Self.key, activationID: Self.activationID)
        XCTAssertEqual(result, .unavailable)
    }

    func testValidateForbiddenIsNotRevoked() async {
        PolarStubURLProtocol.answerWith(#"{"error":"NotPermitted","detail":"License key activation limit already reached"}"#, status: 403)
        let result = await client.validate(key: Self.key, activationID: Self.activationID)
        XCTAssertEqual(result, .unavailable)
    }

    // MARK: Answers that are not Polar's

    func testForbiddenOrNotFoundWithoutPolarsErrorIsCouldNotAsk() async {
        let answers: [(body: String, status: Int)] = [
            ("<html><body>Access denied</body></html>", 403),
            (#"{"detail":"Not Found"}"#, 404),
            ("<html><body>Not Found</body></html>", 404),
            (#"{"error":"","detail":"Not found"}"#, 404),
            ("", 403),
        ]
        for answer in answers {
            PolarStubURLProtocol.answerWith(answer.body, status: answer.status)
            let activation = await client.activate(key: Self.key, label: "Mac")
            XCTAssertEqual(activation, .unavailable, "activate \(answer)")
            let validation = await client.validate(key: Self.key, activationID: Self.activationID)
            XCTAssertEqual(validation, .unavailable, "validate \(answer)")
            let deactivation = await client.deactivate(key: Self.key, activationID: Self.activationID)
            XCTAssertEqual(deactivation, .unavailable, "deactivate \(answer)")
        }
    }

    func testValidateCouldNotAsk() async {
        for status in [429, 500, 502] {
            PolarStubURLProtocol.answerWith("", status: status)
            let result = await client.validate(key: Self.key, activationID: Self.activationID)
            XCTAssertEqual(result, .unavailable, "\(status)")
        }
        for error in [URLError(.timedOut), URLError(.notConnectedToInternet)] {
            PolarStubURLProtocol.failWith(error)
            let result = await client.validate(key: Self.key, activationID: Self.activationID)
            XCTAssertEqual(result, .unavailable, "\(error.code)")
        }
        PolarStubURLProtocol.answerWith("<html>ok</html>")
        let result = await client.validate(key: Self.key, activationID: Self.activationID)
        XCTAssertEqual(result, .unavailable)
    }

    // MARK: Deactivate answers

    func testDeactivateAnswers() async {
        PolarStubURLProtocol.answerWith(#"{"error":"ResourceNotFound","detail":"Not found"}"#, status: 404)
        var result = await client.deactivate(key: Self.key, activationID: Self.activationID)
        XCTAssertEqual(result, .notFound)

        PolarStubURLProtocol.answerWith("", status: 429)
        result = await client.deactivate(key: Self.key, activationID: Self.activationID)
        XCTAssertEqual(result, .unavailable)

        PolarStubURLProtocol.failWith(URLError(.timedOut))
        result = await client.deactivate(key: Self.key, activationID: Self.activationID)
        XCTAssertEqual(result, .unavailable)
    }

    // MARK: Polar's answers

    private static func activated(status: String = "granted") -> String {
        """
        {
          "id": "\(activationID)",
          "license_key_id": "0b6a1c2e-5f3d-4e8a-9b7c-1d2e3f4a5b6c",
          "label": "MacBookPro18,3",
          "meta": {},
          "created_at": "2026-10-05T12:00:00Z",
          "modified_at": null,
          "license_key": {
            "id": "0b6a1c2e-5f3d-4e8a-9b7c-1d2e3f4a5b6c",
            "status": "\(status)",
            "limit_activations": 1,
            "usage": 0,
            "limit_usage": null,
            "expires_at": null
          }
        }
        """
    }

    private static func validated(status: String, activationID: String?) -> String {
        let activation = activationID.map { #"{"id":"\#($0)","label":"MacBookPro18,3","meta":{}}"# } ?? "null"
        return """
        {
          "id": "0b6a1c2e-5f3d-4e8a-9b7c-1d2e3f4a5b6c",
          "organization_id": "\(config.organizationID)",
          "key": "\(key)",
          "display_key": "****-5E6F",
          "status": "\(status)",
          "limit_activations": 1,
          "usage": 0,
          "limit_usage": null,
          "validations": 3,
          "expires_at": null,
          "activation": \(activation)
        }
        """
    }
}

/// Answers every request from canned bytes, the way Polar would have.
final class PolarStubURLProtocol: URLProtocol {
    static var answer: (status: Int, body: Data)?
    static var failure: Error?
    static var requests: [URLRequest] = []
    /// A session hands a protocol the body as a stream rather than as
    /// `httpBody`, so it is read out when the request arrives.
    static var bodies: [Data] = []

    static func reset() {
        answer = nil
        failure = nil
        requests = []
        bodies = []
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PolarStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func answerWith(_ body: String, status: Int = 200) {
        answer = (status: status, body: Data(body.utf8))
        failure = nil
    }

    static func failWith(_ error: Error) {
        answer = nil
        failure = error
    }

    static func lastBody() -> [String: Any]? {
        guard let data = bodies.last else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        Self.bodies.append(request.httpBody ?? Self.read(request.httpBodyStream))
        if let failure = Self.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        guard let answer = Self.answer, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: answer.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
