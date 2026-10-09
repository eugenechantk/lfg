// lfg-unlock — lets a Claude Code or Codex session unlock this Mac's screen
// when a task needs the GUI and nobody is at the desk.
//
//   lfg-unlock unlock   wake the lock screen, submit it, and approve the unlock
//                       through our authorization plug-in (exit 0 = unlocked)
//   lfg-unlock lock     lock the screen again
//   lfg-unlock status   locked/unlocked, and whether the plug-in is installed
//
// No password is stored or typed. The plug-in (macos/unlock/plugin) asks this
// process over a socket that exists only while `unlock` runs, and it grants a
// single ALLOW. Every attempt is appended to ~/.lfg/unlock.log.
// See .claude/feature/mac-unlock.md.
import CoreGraphics
import Foundation
import IOKit.pwr_mgt
import Security
import Darwin

let socketDir = "/tmp/dev.omg.lfg-unlock"
let socketPath = socketDir + "/unlock.sock"
let ruleName = "dev.omg.lfg-unlock.remote"
let pluginPath = "/Library/Security/SecurityAgentPlugins/LFGUnlockPlugin.bundle"
let logPath = NSHomeDirectory() + "/.lfg/unlock.log"
// Only Apple's own code may ask for the ALLOW (in practice the loginwindow SecurityAgent).
let peerRequirement = "anchor apple"
// <sys/un.h> values Swift does not import.
let SOL_LOCAL_: Int32 = 0
let LOCAL_PEERTOKEN_: Int32 = 0x006
let LOCAL_PEERPID_: Int32 = 0x002

func log(_ line: String) {
  let stamp = ISO8601DateFormatter().string(from: Date())
  let entry = "\(stamp) pid=\(getpid()) ppid=\(getppid()) \(line)\n"
  FileHandle.standardError.write(entry.data(using: .utf8)!)
  if let h = FileHandle(forWritingAtPath: logPath) ?? {
    FileManager.default.createFile(atPath: logPath, contents: nil)
    return FileHandle(forWritingAtPath: logPath)
  }() {
    h.seekToEndOfFile()
    h.write(entry.data(using: .utf8)!)
    try? h.close()
  }
}

func screenIsLocked() -> Bool {
  guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
  return (d["CGSSessionScreenIsLocked"] as? Bool) ?? false
}

func pluginInstalled() -> Bool {
  let p = Process()
  p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
  p.arguments = ["authorizationdb", "read", "system.login.screensaver"]
  let out = Pipe()
  p.standardOutput = out
  p.standardError = FileHandle.nullDevice
  guard (try? p.run()) != nil else { return false }
  p.waitUntilExit()
  let rule = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  return rule.contains(ruleName) && FileManager.default.fileExists(atPath: pluginPath)
}

func declareUserActivity() {
  var id: IOPMAssertionID = 0
  IOPMAssertionDeclareUserActivity("lfg-unlock" as CFString, kIOPMUserActiveLocal, &id)
}

func postKeys(_ codes: [CGKeyCode]) {
  let src = CGEventSource(stateID: .hidSystemState)
  for code in codes {
    CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
    usleep(30_000)
    CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
    usleep(120_000)
  }
}

/// The socket the plug-in connects to. The plug-in runs in SecurityAgentHelper
/// as a different user (a 0700 directory gave it EACCES on the first real
/// unlock), so the directory must be traversable and the socket connectable by
/// anyone. That is safe: /tmp is sticky so nobody else can replace our socket,
/// the plug-in checks our code signature, and we answer only Apple-signed peers.
func listenOnSocket() throws -> Int32 {
  let fm = FileManager.default
  var isDir: ObjCBool = false
  if fm.fileExists(atPath: socketDir, isDirectory: &isDir) {
    let attrs = try fm.attributesOfItem(atPath: socketDir)
    guard isDir.boolValue, (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
      throw NSError(domain: "lfg-unlock", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "\(socketDir) is not a directory owned by this user"])
    }
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: socketDir)
  } else {
    try fm.createDirectory(atPath: socketDir, withIntermediateDirectories: false,
                           attributes: [.posixPermissions: 0o755])
  }
  unlink(socketPath)
  let fd = socket(AF_UNIX, SOCK_STREAM, 0)
  guard fd >= 0 else { throw NSError(domain: "lfg-unlock", code: 2) }
  var addr = sockaddr_un()
  addr.sun_family = sa_family_t(AF_UNIX)
  withUnsafeMutableBytes(of: &addr.sun_path) { buf in
    _ = socketPath.withCString { strlcpy(buf.baseAddress!.assumingMemoryBound(to: CChar.self), $0, buf.count) }
  }
  let bound = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
  }
  guard bound == 0, chmod(socketPath, 0o666) == 0, listen(fd, 4) == 0 else {
    close(fd)
    throw NSError(domain: "lfg-unlock", code: 3,
                  userInfo: [NSLocalizedDescriptionKey: "cannot listen on \(socketPath): errno \(errno)"])
  }
  return fd
}

func acceptWithin(_ fd: Int32, seconds: Double) -> Int32? {
  var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
  guard poll(&pfd, 1, Int32(seconds * 1000)) > 0 else { return nil }
  let conn = accept(fd, nil, nil)
  return conn >= 0 ? conn : nil
}

/// Names the peer when it is Apple's code, else nil. Two independent proofs,
/// because the code-signing lookup failed once in two live attempts against
/// the same SecurityAgentHelper process: an Apple signature, or an executable
/// inside SIP-protected /System (which only Apple can write).
func applePeerIdentifier(_ fd: Int32) -> String? {
  var token = audit_token_t()
  var len = socklen_t(MemoryLayout<audit_token_t>.size)
  if getsockopt(fd, SOL_LOCAL_, LOCAL_PEERTOKEN_, &token, &len) == 0 {
    let tokenData = Data(bytes: &token, count: MemoryLayout<audit_token_t>.size)
    var code: SecCode?
    var req: SecRequirement?
    let st1 = SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: tokenData] as CFDictionary, [], &code)
    if st1 == errSecSuccess, let code,
       SecRequirementCreateWithString(peerRequirement as CFString, [], &req) == errSecSuccess {
      let st2 = SecCodeCheckValidity(code, [], req)
      if st2 == errSecSuccess {
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        if SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
           SecCodeCopySigningInformation(staticCode, [], &info) == errSecSuccess,
           let id = (info as? [String: Any])?[kSecCodeInfoIdentifier as String] as? String {
          return id
        }
        return "apple:unknown"
      }
      log("unlock: peer signature check failed status=\(st2)")
    } else {
      log("unlock: peer code lookup failed status=\(st1)")
    }
  }
  var pid: pid_t = 0
  var plen = socklen_t(MemoryLayout<pid_t>.size)
  guard getsockopt(fd, SOL_LOCAL_, LOCAL_PEERPID_, &pid, &plen) == 0, pid > 0 else { return nil }
  var path = [CChar](repeating: 0, count: 4096)
  guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
  let exe = String(cString: path)
  return exe.hasPrefix("/System/Library/Frameworks/Security.framework/") ? "path:\(exe)" : nil
}

/// Serve one plug-in request: check the peer, read its ask, answer ALLOW.
func grant(_ conn: Int32) -> Bool {
  defer { close(conn) }
  guard let peer = applePeerIdentifier(conn) else {
    log("unlock: refused a socket peer that is not Apple-signed")
    return false
  }
  var buf = [UInt8](repeating: 0, count: 32)
  var tv = timeval(tv_sec: 3, tv_usec: 0)
  setsockopt(conn, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
  let n = read(conn, &buf, buf.count - 1)
  guard n > 0, String(decoding: buf[0..<n], as: UTF8.self).hasPrefix("UNLOCK") else {
    log("unlock: peer \(peer) sent no UNLOCK request")
    return false
  }
  let ok = write(conn, "ALLOW\n", 6) == 6
  log("unlock: granted to \(peer) ok=\(ok)")
  return ok
}

/// The command line of whoever ran us, for the audit log (macOS has no /proc).
func parentCommand() -> String {
  let p = Process()
  p.executableURL = URL(fileURLWithPath: "/bin/ps")
  p.arguments = ["-o", "command=", "-p", String(getppid())]
  let out = Pipe()
  p.standardOutput = out
  guard (try? p.run()) != nil else { return "ppid \(getppid())" }
  p.waitUntilExit()
  let cmd = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
  return String(cmd.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
}

/// Test mode: hold the socket open and answer plug-in requests, without touching
/// the screen. Grants exactly what `unlock` would, so it is no wider an opening.
func serve(seconds: Double) -> Int32 {
  log("serve: \(seconds)s caller=\(parentCommand())")
  let fd: Int32
  do { fd = try listenOnSocket() } catch {
    log("serve: \(error.localizedDescription)")
    return 1
  }
  defer {
    close(fd)
    unlink(socketPath)
  }
  let deadline = Date().addingTimeInterval(seconds)
  while Date() < deadline, let conn = acceptWithin(fd, seconds: deadline.timeIntervalSinceNow) {
    _ = grant(conn)
  }
  return 0
}

func unlock() -> Int32 {
  if !screenIsLocked() {
    print("already unlocked")
    return 0
  }
  // Without the plug-in our Return would submit a wrong password; never do that.
  guard pluginInstalled() else {
    log("unlock: plug-in not installed — run macos/unlock/install.sh with sudo")
    return 2
  }
  log("unlock: start caller=\(parentCommand())")
  let fd: Int32
  do { fd = try listenOnSocket() } catch {
    log("unlock: \(error.localizedDescription)")
    return 1
  }
  defer {
    close(fd)
    unlink(socketPath)
  }
  var granted = false
  var pluginAsked = false
  // Submit again only if the keys never reached the form. Once the plug-in has
  // asked, another submit would just be one more failed password attempt.
  for attempt in 1...2 where !granted && !pluginAsked {
    declareUserActivity()
    usleep(1_500_000)  // let loginwindow raise the lock UI and focus the field
    // Return on the empty field submits the form. We used to type "a" first;
    // either way loginwindow then tries that text on the keybag and fails, so
    // an empty field at least never sends a made-up password.
    postKeys([36])
    let deadline = Date().addingTimeInterval(6)
    while !granted, Date() < deadline, let conn = acceptWithin(fd, seconds: deadline.timeIntervalSinceNow) {
      pluginAsked = true
      granted = grant(conn)
    }
    if !pluginAsked { log("unlock: attempt \(attempt) got no plug-in request") }
  }
  guard granted else { return 3 }
  for _ in 0..<40 where screenIsLocked() { usleep(200_000) }
  if screenIsLocked() {
    log("unlock: granted but the screen is still locked")
    return 4
  }
  let sealed = protectedDataSealed() ?? false
  log("unlock: screen unlocked protectedDataSealed=\(sealed)")
  print("unlocked")
  if sealed { print("note: \(sealedNote)") }
  return 0
}

/// The data-protection keybag (iCloud Keychain, saved passwords, Preview
/// signatures). loginwindow locks it at screen lock and unlocks it only with
/// the real password, so after our password-free unlock it stays sealed.
/// nil = cannot tell.
func protectedDataSealed() -> Bool? {
  typealias Fn = @convention(c) (CFDictionary?) -> Int32
  guard let h = dlopen("/System/Library/PrivateFrameworks/MobileKeyBag.framework/MobileKeyBag", RTLD_LAZY),
        let sym = dlsym(h, "MKBGetDeviceLockState") else { return nil }
  return unsafeBitCast(sym, to: Fn.self)(nil) != 0
}

let sealedNote = "iCloud Keychain, saved passwords and Preview signatures stay sealed until Eugene types his password once"

func lock() -> Int32 {
  typealias LockFn = @convention(c) () -> Int32
  guard let h = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
        let sym = dlsym(h, "SACLockScreenImmediate") else {
    log("lock: SACLockScreenImmediate unavailable")
    return 1
  }
  _ = unsafeBitCast(sym, to: LockFn.self)()
  log("lock: requested")
  print("locked")
  return 0
}

func status() -> Int32 {
  print("screen: \(screenIsLocked() ? "locked" : "unlocked")")
  print("plug-in: \(pluginInstalled() ? "installed" : "NOT installed")")
  switch protectedDataSealed() {
  case true?: print("protected data: sealed — \(sealedNote)")
  case false?: print("protected data: available")
  case nil: print("protected data: unknown")
  }
  return 0
}

// A plug-in that hangs up mid-reply must not kill us with SIGPIPE.
signal(SIGPIPE, SIG_IGN)
switch CommandLine.arguments.dropFirst().first {
case "unlock": exit(unlock())
case "lock": exit(lock())
case "status": exit(status())
case "serve": exit(serve(seconds: Double(CommandLine.arguments.dropFirst(2).first ?? "") ?? 10))
default:
  FileHandle.standardError.write("usage: lfg-unlock unlock|lock|status\n".data(using: .utf8)!)
  exit(64)
}
