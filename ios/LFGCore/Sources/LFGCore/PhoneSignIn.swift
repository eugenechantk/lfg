import Foundation

public struct PhoneSignInTarget: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var kind: String
}
public struct PhoneSignInTargets: Decodable, Sendable { public var targets: [PhoneSignInTarget] }
public struct PhoneSignInCookie: Codable, Sendable {
    public var name: String
    public var value: String
    public var domain: String
    public var hostOnly: Bool
    public var path: String
    public var secure: Bool
    public var httpOnly: Bool
    public var sameSite: String?
    public var expires: Double?
    public init(cookie: HTTPCookie) {
        let policy = cookie.sameSitePolicy?.rawValue.lowercased()
        self.init(name: cookie.name, value: cookie.value, domain: cookie.domain,
                  hostOnly: !cookie.domain.hasPrefix("."), path: cookie.path,
                  secure: cookie.isSecure, httpOnly: cookie.isHTTPOnly,
                  sameSite: ["strict": "Strict", "lax": "Lax", "none": "None"][policy ?? ""],
                  expires: cookie.isSessionOnly ? nil : cookie.expiresDate?.timeIntervalSince1970)
    }
    public init(name:String,value:String,domain:String,hostOnly:Bool,path:String,secure:Bool,httpOnly:Bool,sameSite:String?=nil,expires:Double?=nil) {
        self.name=name;self.value=value;self.domain=domain;self.hostOnly=hostOnly;self.path=path;self.secure=secure;self.httpOnly=httpOnly;self.sameSite=sameSite;self.expires=expires
    }
}
public struct PhoneSignInTransfer: Encodable, Sendable {
    public var targetId: String
    public var url: String
    public var domains: [String]
    public var cookies: [PhoneSignInCookie]
    public init(targetId:String,url:String,domains:[String],cookies:[PhoneSignInCookie]) {self.targetId=targetId;self.url=url;self.domains=domains;self.cookies=cookies}
}
public struct PhoneSignInResult: Decodable, Sendable {
    public var state: String
    public var installed: Int
    public var total: Int
    public var message: String {
        switch state {
        case "installed": return "Sign-in sent. Refresh the website in your browser, then continue with the agent."
        case "partial": return "Only \(installed) of \(total) cookies were installed. Check the destination before trying again."
        case "failed": return "No cookies were installed. Check the browser’s website permissions."
        default: return "Delivery could not be confirmed. Check the destination browser before trying again."
        }
    }
}
public enum PhoneSignInPolicy {
    /// Account controls are a conservative hint, not a universal authentication API.
    /// Explicit user confirmation supports sites whose UI cannot be recognized.
    public static func canFinish(hasCookies: Bool, loading: Bool, hasLoginFields: Bool,
                                 hasAccountControls: Bool, onRequestedHost: Bool, userConfirmed: Bool) -> Bool {
        hasCookies && !loading && (userConfirmed || (onRequestedHost && !hasLoginFields && hasAccountControls))
    }

    public static func loginURL(_ input:String) throws -> URL {
        var text=input.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !text.isEmpty else {throw LFGError.badURL}
        if !text.contains(":") {text="https://"+text}
        guard let url=URL(string:text), let host=url.host, !host.isEmpty, url.user==nil, url.password==nil,
              url.scheme=="https" || (url.scheme=="http" && ["localhost","127.0.0.1","::1","[::1]"].contains(host)) else {throw LFGError.badURL}
        return url
    }
    public static func domain(_ input:String) -> String { input.hasPrefix(".") ? String(input.dropFirst()).lowercased() : input.lowercased() }
    public static func selectedCookies(_ cookies:[PhoneSignInCookie],domains:Set<String>,now:Date=Date()) -> [PhoneSignInCookie] {
        cookies.filter { domains.contains(domain($0.domain)) && ($0.expires == nil || $0.expires! > now.timeIntervalSince1970) }
    }
}


/// Metadata only: no cookies or credentials appear in agent requests.
public struct PhoneSignInAgentRequest: Decodable, Sendable, Identifiable {
    public let id: String
    public let sessionId: String
    public let url: String
    public let target: PhoneSignInTarget
    public let state: String
    public let createdAt: Double
    public let expiresAt: Double
    public let result: PhoneSignInResult?
    public var website: String { URL(string: url)?.host ?? "website" }
    public var isWaiting: Bool { state == "waiting" }
    public var requestedAt: Date { Date(timeIntervalSince1970: createdAt / 1000) }
    public var statusTitle: String {
        switch state {
        case "waiting": "Waiting for sign-in"
        case "delivering": "Sending"
        case "installed": "Sent"
        case "partial": "Partially sent"
        case "failed": "Failed"
        case "cancelled": "Cancelled"
        case "expired": "Expired"
        case "offline": "Browser disconnected"
        default: "Delivery unconfirmed"
        }
    }
    public var statusSystemImage: String {
        switch state {
        case "waiting": "key.fill"
        case "delivering": "arrow.up.circle"
        case "installed": "checkmark.circle"
        case "cancelled": "xmark.circle"
        case "expired": "clock"
        default: "exclamationmark.circle"
        }
    }
    public var message: String {
        switch state {
        case "installed": "Sign-in sent. Your agent can continue."
        case "cancelled": "Sign-in cancelled. Your agent has been notified."
        case "expired": "This sign-in request expired. Ask the agent to request it again."
        case "offline": "The requested browser disconnected. Ask the agent for a new sign-in request."
        case "delivering": "Sign-in delivery is in progress. Check its status before trying again."
        default: result?.message ?? "Delivery could not be confirmed. Check the destination browser."
        }
    }
}
public struct PhoneSignInAgentRequests: Decodable, Sendable { public let requests: [PhoneSignInAgentRequest] }
