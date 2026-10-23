import Foundation

/// How activating a key on this Mac went.
enum LicenseActivation: Equatable, Sendable {
    /// Polar counted this Mac against the key, under this activation id.
    /// - Parameter macs: on how many Macs the key runs, when Polar says so.
    /// - Parameter purchased: when the key was made, which is when it was
    ///   bought, when Polar says so.
    case activated(id: String, macs: Int? = nil, purchased: Date? = nil)
    /// Every activation of the key is held by another Mac.
    case limitReached
    /// Polar does not know the key.
    case notFound
    /// Polar knows the key and will not honour it: revoked, disabled or expired.
    case revoked
    /// Polar could not be asked, or did not answer in a way that says anything
    /// about the key.
    case unavailable
}

/// What Polar says about this Mac's activation of a key.
enum LicenseValidation: Equatable, Sendable {
    /// The key is granted and the activation is this Mac's.
    /// - Parameter purchased: when the key was made, which is when it was
    ///   bought, when Polar says so.
    case valid(purchased: Date? = nil)
    /// The activation is gone (freed from another Mac or the portal), or the
    /// key is unknown.
    case notFound
    /// The key was revoked or disabled.
    case revoked
    /// Nothing is known either way.
    case unavailable
}

/// How freeing this Mac's activation went.
enum LicenseDeactivation: Equatable, Sendable {
    case deactivated
    /// There was nothing to free: the activation or the key is gone already.
    case notFound
    case unavailable
}

/// The three calls the license state needs, so tests can answer them without
/// a network.
protocol LicenseAPI: Sendable {
    func activate(key: String, label: String) async -> LicenseActivation
    func validate(key: String, activationID: String) async -> LicenseValidation
    func deactivate(key: String, activationID: String) async -> LicenseDeactivation
}

/// Activates, validates and deactivates a key through Polar's public customer
/// portal endpoints under `/v1/customer-portal/license-keys/`, which need no
/// token and are meant for an app on somebody's own computer.
///
/// Validate always carries this Mac's activation id. Without one, Polar answers
/// 200 for any real key, also when another Mac holds its activation.
struct LicenseClient: LicenseAPI {
    private static let path = "v1/customer-portal/license-keys"
    /// Short enough that a dead network is not a long spinner under the key
    /// field.
    private static let timeout: TimeInterval = 15

    let config: LicenseConfig
    /// Injectable so the tests answer from canned JSON and never reach Polar.
    let session: URLSession

    init(config: LicenseConfig = .current, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    /// A key as the user pasted it, without the spaces and line breaks a copy
    /// from an email or a receipt brings along.
    static func cleaned(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func activate(key: String, label: String) async -> LicenseActivation {
        let key = Self.cleaned(key)
        guard !key.isEmpty else { return .notFound }
        let body = ActivateBody(key: key, organizationID: config.organizationID, label: label, meta: [:])
        switch await post("activate", body: body) {
        case .ok(let data):
            guard let activated = try? JSONDecoder().decode(Activated.self, from: data) else {
                return .unavailable
            }
            guard activated.licenseKey.status == "granted" else { return .revoked }
            return .activated(
                id: activated.id, macs: activated.licenseKey.limitActivations,
                purchased: activated.licenseKey.createdAt.flatMap(UpdateWindow.polarDate)
            )
        case .forbidden(let detail):
            return detail.contains("limit") ? .limitReached : .revoked
        case .notFound(let detail):
            return Self.isInactive(detail) ? .revoked : .notFound
        case .failed:
            return .unavailable
        }
    }

    func validate(key: String, activationID: String) async -> LicenseValidation {
        let key = Self.cleaned(key)
        guard !key.isEmpty, !activationID.isEmpty else { return .notFound }
        let body = ActivationBody(key: key, organizationID: config.organizationID, activationID: activationID)
        switch await post("validate", body: body) {
        case .ok(let data):
            guard let validated = try? JSONDecoder().decode(Validated.self, from: data) else {
                return .unavailable
            }
            guard validated.status == "granted" else { return .revoked }
            // Only an answer about this Mac's own activation proves a license,
            // and an answer about none says nothing either way.
            guard validated.activation?.id == activationID else { return .unavailable }
            return .valid(purchased: validated.createdAt.flatMap(UpdateWindow.polarDate))
        case .forbidden:
            // Polar answers an inactive key with a 404 or a status, never a
            // 403, so a 403 here says nothing about the key.
            return .unavailable
        case .notFound(let detail):
            return Self.isInactive(detail) ? .revoked : .notFound
        case .failed:
            return .unavailable
        }
    }

    func deactivate(key: String, activationID: String) async -> LicenseDeactivation {
        let key = Self.cleaned(key)
        guard !key.isEmpty, !activationID.isEmpty else { return .notFound }
        let body = ActivationBody(key: key, organizationID: config.organizationID, activationID: activationID)
        switch await post("deactivate", body: body) {
        case .ok:
            return .deactivated
        case .notFound:
            return .notFound
        case .forbidden, .failed:
            return .unavailable
        }
    }

    // MARK: - Asking Polar

    private enum Answer {
        /// A 2xx, with its body (empty for a 204).
        case ok(Data)
        /// 403 from Polar itself, with its `detail` lowercased.
        case forbidden(String)
        /// 404 from Polar itself, with its `detail` lowercased.
        case notFound(String)
        /// No answer, or one that says nothing about the key: a network
        /// failure, a timeout, a rate limit, a server error, a request Polar
        /// could not read, or a 403 or 404 that did not come from Polar.
        case failed
    }

    private func post(_ endpoint: String, body: some Encodable) async -> Answer {
        var request = URLRequest(url: config.apiBase.appendingPathComponent("\(Self.path)/\(endpoint)"))
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return .failed
        }
        guard let http = response as? HTTPURLResponse else { return .failed }
        switch http.statusCode {
        case 200..<300:
            return .ok(data)
        case 403, 404:
            // A proxy, a block page or an unknown route answers 403 or 404
            // too. Only Polar's own errors carry an `error` name.
            guard let error = try? JSONDecoder().decode(ErrorBody.self, from: data),
                  let name = error.error, !name.isEmpty else { return .failed }
            let detail = (error.detail ?? "").lowercased()
            return http.statusCode == 403 ? .forbidden(detail) : .notFound(detail)
        default:
            return .failed
        }
    }

    /// Polar answers a revoked, disabled or expired key with a 404 like an
    /// unknown one, and only the sentence in `detail` tells them apart.
    private static func isInactive(_ detail: String) -> Bool {
        detail.contains("no longer active") || detail.contains("expired")
    }

    private struct ActivateBody: Encodable {
        let key: String
        let organizationID: String
        let label: String
        let meta: [String: String]

        enum CodingKeys: String, CodingKey {
            case key
            case organizationID = "organization_id"
            case label
            case meta
        }
    }

    private struct ActivationBody: Encodable {
        let key: String
        let organizationID: String
        let activationID: String

        enum CodingKeys: String, CodingKey {
            case key
            case organizationID = "organization_id"
            case activationID = "activation_id"
        }
    }

    private struct Activated: Decodable {
        struct Key: Decodable {
            let status: String
            let limitActivations: Int?
            let createdAt: String?

            enum CodingKeys: String, CodingKey {
                case status
                case limitActivations = "limit_activations"
                case createdAt = "created_at"
            }
        }

        let id: String
        let licenseKey: Key

        enum CodingKeys: String, CodingKey {
            case id
            case licenseKey = "license_key"
        }
    }

    private struct Validated: Decodable {
        struct Activation: Decodable {
            let id: String
        }

        let status: String
        let activation: Activation?
        /// When the key was made.
        let createdAt: String?

        enum CodingKeys: String, CodingKey {
            case status
            case activation
            case createdAt = "created_at"
        }
    }

    private struct ErrorBody: Decodable {
        let error: String?
        let detail: String?
    }
}
