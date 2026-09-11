import Foundation
import Testing
@testable import LFGCore

@Suite struct BrowserStreamTests {
    @Test func streamRequestUsesOwningHostAndAccessCredential() {
        let client = LFGClient(baseURL: URL(string:"https://mac.example.com/prefix")!, accessCredential: CloudflareAccessCredential(clientID:"id",clientSecret:"secret"))
        let request = client.browserStreamRequest()
        #expect(request.url?.absoluteString == "wss://mac.example.com/prefix/api/browser/stream")
        #expect(request.value(forHTTPHeaderField:"CF-Access-Client-Id") == "id")
        #expect(request.value(forHTTPHeaderField:"CF-Access-Client-Secret") == "secret")
    }
    @Test func localStreamUsesWS() {
        #expect(LFGClient(baseURL:URL(string:"http://127.0.0.1:9981")!).browserStreamRequest().url?.scheme == "ws")
    }
    @Test func decodesWindowAndPermissionFailure() throws {
        let windows = try JSONDecoder().decode(BrowserStreamMessage.self,from:Data(#"{"type":"windows","windows":[{"id":7,"app":"Chrome","title":"Login"}],"accessibility":false}"#.utf8))
        #expect(windows.windows?.first?.id == 7)
        #expect(windows.accessibility == false)
        let error = try JSONDecoder().decode(BrowserStreamMessage.self,from:Data(#"{"type":"error","message":"Permission required"}"#.utf8))
        #expect(error.message == "Permission required")
    }
    @Test func encodesTextAsDataNotShellOrChat() throws {
        let command = BrowserStreamCommand(type:"text",seq:3,frameId:7,text:"密碼'$`🙂")
        let data = try JSONEncoder().encode(command)
        let object = try #require(JSONSerialization.jsonObject(with:data) as? [String:Any])
        #expect(object["text"] as? String == "密碼'$`🙂")
        #expect(object["seq"] as? Int == 3)
        #expect(object["frameId"] as? Int == 7)
    }
}
