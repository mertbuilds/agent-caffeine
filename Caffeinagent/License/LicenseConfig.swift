import Foundation

/// Where license keys are sold and checked.
///
/// One product on Polar: a key for life that runs on 3 Macs and covers the
/// builds released in its first year (`UpdateWindow`). The license key
/// benefit sets the number of activations, and the price is on the site. The
/// keys of the earlier products (1 Mac and 3 Macs) are of the same
/// organization and keep working. A Debug build talks to Polar's sandbox, so
/// a test purchase never touches real money or real keys; a Release build
/// talks to Polar itself. The two are separate organizations with separate ids.
struct LicenseConfig: Equatable, Sendable {
    /// The root of Polar's API, without the `/v1` part.
    let apiBase: URL
    /// The Polar organization the keys belong to. Every call names it, because
    /// a key string is only unique inside one organization.
    let organizationID: String
    /// Where a key is bought: the checkout link of the product.
    let checkoutURL: URL
    /// Where a buyer sees their keys and frees an activation.
    let customerPortalURL: URL

    static let sandbox = LicenseConfig(
        apiBase: URL(string: "https://sandbox-api.polar.sh")!,
        organizationID: "904c54ce-20e8-4a7e-bee9-fef5f8990517",
        checkoutURL: URL(string: "https://sandbox-api.polar.sh/v1/checkout-links/polar_cl_OEmXItlVovnBcDHZclCzzTxLmQFJoOgg7KiQT2wpuq6/redirect")!,
        customerPortalURL: URL(string: "https://sandbox.polar.sh/mertbuilds/portal")!
    )

    static let production = LicenseConfig(
        apiBase: URL(string: "https://api.polar.sh")!,
        organizationID: "6fd87dcb-ab66-439b-8c83-5b2eb5836da6",
        checkoutURL: URL(string: "https://buy.polar.sh/polar_cl_uVXeh4hiiZ6r8meBrBlGm6ZIP7BXKMQrN7eoR0nsbht")!,
        customerPortalURL: URL(string: "https://polar.sh/mertbuilds/portal")!
    )

    /// The one this build uses.
    static var current: LicenseConfig {
        #if DEBUG
        return sandbox
        #else
        return production
        #endif
    }
}
