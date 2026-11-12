import Foundation

/// Reads a PocketBase token's `exp` claim. Beszel's hub gives user tokens 5 days, and it does not
/// answer an expired token with 401 on list calls: it answers 200 with an empty list. So the app
/// must renew a token before it expires, or it silently sees no systems and the graphs stop.
enum TokenExpiry {
    /// Renew this long before the token expires.
    static let margin: TimeInterval = 3600

    /// The token's expiry, or nil when it carries no readable `exp`.
    static func expiry(of token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = claims["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    /// True when the token expires within `margin` of `now`. A token without `exp` is kept.
    static func needsRenewal(_ token: String, now: Date = Date()) -> Bool {
        guard let expiry = expiry(of: token) else { return false }
        return expiry.timeIntervalSince(now) < margin
    }
}
