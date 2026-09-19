import Foundation
import Testing
@testable import LFGCore

@Test func phoneSignInRequiresSecureURLs() throws {
    #expect(try PhoneSignInPolicy.loginURL("example.com").absoluteString == "https://example.com")
    for input in ["http://example.com", "javascript:alert(1)", "https://user:pass@example.com", ""] {
        #expect(throws: (any Error).self) { try PhoneSignInPolicy.loginURL(input) }
    }
    #expect(try PhoneSignInPolicy.loginURL("http://127.0.0.1:9982/login").port == 9982)
}
@Test func phoneSignInFiltersExactDomainsAndPreservesCookieFlags() throws {
    let cookies = [PhoneSignInCookie(name:"session",value:"test",domain:".example.com",hostOnly:false,path:"/",secure:true,httpOnly:true), PhoneSignInCookie(name:"other",value:"hidden",domain:"auth.other.com",hostOnly:true,path:"/",secure:true,httpOnly:true)]
    let selected = PhoneSignInPolicy.selectedCookies(cookies, domains:["example.com"])
    #expect(selected.count == 1)
    let data = try JSONEncoder().encode(selected[0])
    let decoded = try JSONDecoder().decode(PhoneSignInCookie.self,from:data)
    #expect(decoded.httpOnly && decoded.secure && !decoded.hostOnly)
    #expect(decoded.expires == nil)
    #expect(PhoneSignInPolicy.selectedCookies(cookies, domains:["com"]).isEmpty)
}
@Test func phoneSignInRequestUsesOwningHostCredentialsAndRejectsPlaintext() throws {
    let client=LFGClient(baseURL:URL(string:"https://mac.example")!,accessCredential:.init(clientID:"id",clientSecret:"secret"))
    let payload=PhoneSignInTransfer(targetId:"target",url:"https://example.com",domains:["example.com"],cookies:[])
    let request=try client.phoneSignInRequest(payload)
    #expect(request.url?.host == "mac.example")
    #expect(request.value(forHTTPHeaderField:"CF-Access-Client-Secret") == "secret")
    #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    #expect(throws:(any Error).self){try LFGClient(baseURL:URL(string:"http://mac.example")!).phoneSignInRequest(payload)}
}

@Test func phoneSignInExtractsFoundationCookieAttributes() throws {
    let cookie = try #require(HTTPCookie(properties: [
        .name: "session", .value: "synthetic", .domain: ".example.com", .path: "/account",
        .secure: "TRUE", .sameSitePolicy: HTTPCookieStringPolicy.sameSiteStrict.rawValue,
        HTTPCookiePropertyKey("HttpOnly"): "TRUE"
    ]))
    let wire = PhoneSignInCookie(cookie: cookie)
    #expect(wire.sameSite == "Strict")
    #expect(wire.secure && wire.httpOnly && !wire.hostOnly)
    #expect(wire.path == "/account")
    #expect(wire.expires == nil)
}

@Test func agentSignInDoneSendsAllDomainsWithoutClientRetargeting() throws {
    let client = LFGClient(baseURL: URL(string: "https://host.example.com")!)
    let values = [
        PhoneSignInCookie(name: "portal", value: "synthetic", domain: ".example.com", hostOnly: false, path: "/", secure: true, httpOnly: true),
        PhoneSignInCookie(name: "sso", value: "synthetic", domain: "id.example.net", hostOnly: true, path: "/", secure: true, httpOnly: true)
    ]
    let request = try client.agentPhoneSignInRequest("request-id", cookies: values)
    #expect(request.url?.path == "/api/browser-sign-in/requests/request-id/complete")
    let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
    #expect(Set(body.keys) == ["cookies"])
    #expect((body["cookies"] as? [[String: Any]])?.count == 2)
    #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
}

@Test func phoneSignInHistoryDistinguishesOutcomesAndDecodesMilliseconds() throws {
    let labels = ["waiting":"Waiting for sign-in", "delivering":"Sending", "installed":"Sent", "partial":"Partially sent", "failed":"Failed", "cancelled":"Cancelled", "expired":"Expired", "offline":"Browser disconnected", "unknown":"Delivery unconfirmed"]
    for (state, title) in labels {
        let data = try JSONSerialization.data(withJSONObject: ["id":"r", "sessionId":"s", "url":"https://portal.example.com", "target":["id":"b","name":"Browser","kind":"playwright"], "state":state, "createdAt":1234000, "expiresAt":2234000])
        let request = try JSONDecoder().decode(PhoneSignInAgentRequest.self, from:data)
        #expect(request.statusTitle == title)
        #expect(request.isWaiting == (state == "waiting"))
        #expect(request.requestedAt.timeIntervalSince1970 == 1234)
        #expect(request.website == "portal.example.com")
    }
}


@Test func phoneSignInDropsSameSiteNoneOnInsecureCookies() throws {
    let insecure = try #require(HTTPCookie(properties: [.name: "aa", .value: "x", .domain: ".apple.com", .path: "/", .sameSitePolicy: "None"]))
    #expect(PhoneSignInCookie(cookie: insecure).sameSite == nil)
    let secure = try #require(HTTPCookie(properties: [.name: "aa", .value: "x", .domain: ".apple.com", .path: "/", .secure: "TRUE", .sameSitePolicy: "Lax"]))
    #expect(PhoneSignInCookie(cookie: secure).sameSite == "Lax")
}
