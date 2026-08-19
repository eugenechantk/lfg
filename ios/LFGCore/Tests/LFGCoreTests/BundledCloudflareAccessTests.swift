import Foundation
import Testing
@testable import LFGCore

@Suite("Bundled Cloudflare Access")
struct BundledCloudflareAccessTests {
    @Test("decodes and canonicalizes a complete HTTPS configuration")
    func decodesValidConfiguration() throws {
        let data = try #require(
            #"{"hostURL":"  https://lfg.example.com/  ","clientID":" id ","clientSecret":" secret "}"#
                .data(using: .utf8)
        )

        let configuration = try #require(BundledCloudflareAccessConfiguration(data: data))

        #expect(configuration.hostURL == "https://lfg.example.com")
        #expect(configuration.credential.clientID == "id")
        #expect(configuration.credential.clientSecret == "secret")
    }

    @Test("rejects incomplete, malformed, or non-HTTPS configurations", arguments: [
        #"{}"#,
        #"{"hostURL":"https://lfg.example.com","clientID":"","clientSecret":"secret"}"#,
        #"{"hostURL":"http://lfg.example.com","clientID":"id","clientSecret":"secret"}"#,
        #"{"hostURL":"https://lfg.example.com/path","clientID":"id","clientSecret":"secret"}"#,
        #"{"hostURL":"not a URL","clientID":"id","clientSecret":"secret"}"#,
    ])
    func rejectsUnsafeConfiguration(json: String) {
        #expect(BundledCloudflareAccessConfiguration(data: Data(json.utf8)) == nil)
    }

    @Test("adds a bundled host only when it is not already configured")
    func bootstrapsHostWithoutDuplicates() throws {
        let data = Data(
            #"{"hostURL":"https://lfg.example.com","clientID":"id","clientSecret":"secret"}"#.utf8
        )
        let configuration = try #require(BundledCloudflareAccessConfiguration(data: data))

        let inserted = configuration.addingHostIfNeeded(to: [])
        #expect(inserted == [Host(url: "https://lfg.example.com", isDefault: true)])

        let existing = [Host(url: "https://LFG.example.com/", displayName: "My Mac", isDefault: true)]
        #expect(configuration.addingHostIfNeeded(to: existing) == existing)
    }

    @Test("preserves an existing default when adding the bundled host")
    func preservesExistingDefault() throws {
        let data = Data(
            #"{"hostURL":"https://lfg.example.com","clientID":"id","clientSecret":"secret"}"#.utf8
        )
        let configuration = try #require(BundledCloudflareAccessConfiguration(data: data))
        let current = [Host(url: "https://other.example.com", isDefault: true)]

        let result = configuration.addingHostIfNeeded(to: current)

        #expect(result.map(\.url) == ["https://other.example.com", "https://lfg.example.com"])
        #expect(result.map(\.isDefault) == [true, false])
    }
}
