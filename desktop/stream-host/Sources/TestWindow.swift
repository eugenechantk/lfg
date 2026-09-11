#if DEBUG
import AppKit

/// Disposable native acceptance surface; never connects to an account or website.
@MainActor final class StreamTestWindow: NSObject, NSTextFieldDelegate {
    let window = NSWindow(contentRect:NSRect(x:100,y:100,width:800,height:600),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
    let text = NSTextField(frame:NSRect(x:60,y:370,width:600,height:44))
    let password = NSSecureTextField(frame:NSRect(x:60,y:285,width:600,height:44))
    let label = NSTextField(labelWithString:"Clicks: 0")
    var count = 0
    var timer: Timer?
    override init() {
        super.init()
        window.title = "LFG Stream Acceptance"
        window.isReleasedWhenClosed = false
        let content = window.contentView!
        let title = NSTextField(labelWithString:"Remote input test")
        title.font = .systemFont(ofSize:26,weight:.semibold); title.frame = NSRect(x:60,y:505,width:600,height:40)
        content.addSubview(title)
        let clock = NSTextField(labelWithString:"")
        clock.frame = NSRect(x:60,y:455,width:600,height:30); content.addSubview(clock)
        timer = Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { _ in
            clock.stringValue = "Live frame: \(Date().formatted(date:.omitted,time:.standard)) · \(Int(Date().timeIntervalSince1970*10)%10)"
        }
        text.placeholderString = "Ordinary text"; text.delegate = self; content.addSubview(text)
        password.placeholderString = "Test password only"; password.delegate = self; content.addSubview(password)
        let button = NSButton(title:"Click test",target:self,action:#selector(clicked))
        button.frame = NSRect(x:60,y:195,width:180,height:44); content.addSubview(button)
        label.frame = NSRect(x:280,y:200,width:300,height:30); content.addSubview(label)
        let scroll = NSScrollView(frame:NSRect(x:60,y:20,width:650,height:135))
        let document = NSTextView(frame:NSRect(x:0,y:0,width:630,height:1000))
        document.string = (1...40).map { "Scroll row \($0)" }.joined(separator:"\n")
        document.isEditable = false; scroll.documentView = document; scroll.hasVerticalScroller = true
        content.addSubview(scroll)
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        wire.send(["event":"testWindow","pid":getpid(),"windowId":window.windowNumber])
    }
    @objc func clicked() { count += 1; label.stringValue = "Clicks: \(count)"; wire.send(["event":"click","count":count]) }
    func controlTextDidChange(_ notification:Notification) {
        // This test-only app handles synthetic acceptance text, never real credentials.
        if let field = notification.object as? NSTextField {
            wire.send(["event":field === password ? "testPassword" : "testText","value":field.stringValue])
        }
    }
}
#endif
