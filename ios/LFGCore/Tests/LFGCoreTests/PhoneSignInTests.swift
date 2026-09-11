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
