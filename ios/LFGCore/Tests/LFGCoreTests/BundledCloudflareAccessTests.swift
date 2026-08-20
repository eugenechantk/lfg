import Foundation
import Testing
@testable import LFGCore

@Suite("Bundled Cloudflare Access")
struct BundledCloudflareAccessTests {
    @Test("decodes and canonicalizes an ordered multi-host HTTPS configuration")
    func decodesValidMultiHostConfiguration() throws {
        let data = try #require(
            #"{"hostURLs":["  https://lfg-pro.example.com/  ","https://LFG-Air.example.com","https://lfg-pro.example.com"],"clientID":" id ","clientSecret":" secret "}"#
                .data(using: .utf8)
        )

        let configuration = try #require(BundledCloudflareAccessConfiguration(data: data))

        #expect(configuration.hostURLs == [
            "https://lfg-pro.example.com",
            "https://lfg-air.example.com",
        ])
        #expect(configuration.credential.clientID == "id")
        #expect(configuration.credential.clientSecret == "secret")
    }

    @Test("accepts the legacy single-host payload")
    func decodesLegacyConfiguration() throws {
        let data = Data(
            #"{"hostURL":"https://lfg.example.com","clientID":"id","clientSecret":"secret"}"#.utf8
        )

        let configuration = try #require(BundledCloudflareAccessConfiguration(data: data))

        #expect(configuration.hostURLs == ["https://lfg.example.com"])
    }

    @Test("rejects incomplete, malformed, or non-HTTPS configurations", arguments: [
        #"{}"#,
        #"{"hostURLs":[],"hostURL":"https://lfg.example.com","clientID":"id","clientSecret":"secret"}"#,
        #"{"hostURLs":["https://lfg.example.com","http://unsafe.example.com"],"clientID":"id","clientSecret":"secret"}"#,
        #"{"hostURL":"https://lfg.example.com","clientID":"","clientSecret":"secret"}"#,
        #"{"hostURL":"http://lfg.example.com","clientID":"id","clientSecret":"secret"}"#,
        #"{"hostURL":"https://lfg.example.com/path","clientID":"id","clientSecret":"secret"}"#,
        #"{"hostURL":"not a URL","clientID":"id","clientSecret":"secret"}"#,
    ])
    func rejectsUnsafeConfiguration(json: String) {
        #expect(BundledCloudflareAccessConfiguration(data: Data(json.utf8)) == nil)
    }

    @Test("adds all bundled hosts only when they are not already configured")
    func bootstrapsHostsWithoutDuplicates() throws {
        let data = Data(
            #"{"hostURLs":["https://lfg-pro.example.com","https://lfg-air.example.com"],"clientID":"id","clientSecret":"secret"}"#.utf8
        )
        let configuration = try #require(BundledCloudflareAccessConfiguration(data: data))

        let inserted = configuration.addingHostsIfNeeded(to: [])
        #expect(inserted == [
            Host(url: "https://lfg-pro.example.com", isDefault: true),
            Host(url: "https://lfg-air.example.com"),
        ])

        let existing = [
            Host(url: "https://LFG-Pro.example.com/", displayName: "My Mac", isDefault: true),
        ]
        #expect(configuration.addingHostsIfNeeded(to: existing) == [
            existing[0],
            Host(url: "https://lfg-air.example.com"),
        ])
    }

    @Test("preserves an existing default when adding the bundled host")
    func preservesExistingDefault() throws {
        let data = Data(
            #"{"hostURL":"https://lfg.example.com","clientID":"id","clientSecret":"secret"}"#.utf8
        )
        let configuration = try #require(BundledCloudflareAccessConfiguration(data: data))
        let current = [Host(url: "https://other.example.com", isDefault: true)]

        let result = configuration.addingHostsIfNeeded(to: current)

        #expect(result.map(\.url) == ["https://other.example.com", "https://lfg.example.com"])
        #expect(result.map(\.isDefault) == [true, false])
    }
}
