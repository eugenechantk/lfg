import AppKit
import Darwin

/// Discovers the terminal from live tmux clients, never from window titles.
/// Remote clients launched by LFG carry iTerm's stable session ID through SSH
/// or Mosh. It belongs to the client, so switching tmux sessions stays correct.
enum DesktopITerm {
    enum FocusResult: Equatable { case focused, notFound, failed(String) }

    struct Discovery {
        var ttys = Set<String>()
        var ids = Set<String>()
        var error: String?

        var earlyFocusResult: FocusResult? {
            if let error { return .failed(error) }
            return ttys.isEmpty && ids.isEmpty ? .notFound : nil
        }
    }

    static func focus(_ item: SessionItem) -> FocusResult {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2").isEmpty == false else { return .notFound }
        let found = discover(item)
        if let result = found.earlyFocusResult { return result }
        let result = Opener.runAppleScript(focusScript(ttys: found.ttys, ids: found.ids))
        if let error = result.err { return .failed("iTerm2 couldn’t select the session: \(error)") }
        return result.out == "focused" ? .focused : .notFound
    }

    /// Read-only so diagnostics can inspect real attachments without opening one.
    static func discover(_ item: SessionItem) -> Discovery {
        guard let name = item.session.tmuxName else { return Discovery() }
        var found = Discovery()
        if item.hostIsLocal {
            let result = run(Opener.tmux, ["list-clients", "-F", "#{session_name}\t#{client_tty}"])
            guard result.status == 0 else {
                return Discovery(error: "Couldn’t check existing terminal connections on this Mac. Try again.")
            }
            found.ttys = localTTYs(result.output, session: name)
        } else if let target = item.hostSSHTarget {
            let result = run("/usr/bin/ssh", ["-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", target,
                                          remoteDiscoveryCommand(session: name)], timeout: 8)
            if result.status == 0 {
                let discovery = parseRemoteDiscovery(result.output)
                found.ids = discovery.ids
                if !discovery.legacyTargets.isEmpty || !discovery.moshPorts.isEmpty {
                    // Existing windows predate identity tracking. Match the exact
                    // host and original attach argument, only when unambiguous.
                    let processes = terminalProcesses()
                    for original in discovery.legacyTargets {
                        let matches = Set(processes.filter {
                            matchesRemote(arguments: $0.arguments, host: target, session: original)
                        }.map(\.tty))
                        if matches.count == 1 { found.ttys.formUnion(matches) }
                    }
                    found.ttys.formUnion(moshBridgeTTYs(processes, host: target, ports: discovery.moshPorts))
                }
            } else {
                found.error = "Couldn’t check existing terminal connections on \(item.hostSSHTarget ?? "the remote host"). Reconnect the host and try again."
            }
        }
        return found
    }

    static func localTTYs(_ output: String, session: String) -> Set<String> {
        Set(output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 2, fields[0] == session, fields[1].hasPrefix("/dev/") else { return nil }
            return String(fields[1])
        })
    }

    static func remoteDiscoveryCommand(session: String) -> String {
        // Only terminal markers, attach argv, and Mosh ports leave the host.
        """
        PATH=/opt/homebrew/bin:/usr/local/bin:$PATH
        export PATH
        tmux list-clients -F '#{session_name}\t#{client_pid}' | while IFS="$(printf '\\t')" read -r name pid; do
          [ "$name" = \(Opener.shq(session)) ] || continue
          case "$pid" in ''|*[!0-9]*) continue ;; esac
          marker=$(ps eww -p "$pid" -o command= | awk '{for(i=1;i<=NF;i++) if($i ~ /^LFG_ITERM_SESSION_ID=[a-zA-Z0-9:.-]+$/) {sub(/^LFG_ITERM_SESSION_ID=/,"",$i); print $i; exit}}')
          if [ -n "$marker" ]; then printf 'ID\\t%s\\n' "$marker";
          else
            printf 'ARGV\\t'; ps -ww -p "$pid" -o command=
            ancestor=$pid
            depth=0
            while [ "$ancestor" -gt 1 ] && [ "$depth" -lt 32 ]; do
              command=$(ps -p "$ancestor" -o comm=)
              case "$command" in
                mosh-server|*/mosh-server)
                  /usr/sbin/lsof -nP -a -p "$ancestor" -iUDP -Fn 2>/dev/null | awk '/^n/ {sub(/^n.*:/, ""); if ($0 ~ /^[0-9]+$/) printf "PORT\\t%s\\n", $0}'
                  break ;;
              esac
              parent=$(ps -p "$ancestor" -o ppid= | tr -d ' ')
              case "$parent" in ''|*[!0-9]*) break ;; esac
              [ "$parent" -ne "$ancestor" ] || break
              ancestor=$parent
              depth=$((depth + 1))
            done
          fi
        done
        """
    }

    static func parseRemoteDiscovery(_ text: String) -> (ids: Set<String>, legacyTargets: Set<String>, moshPorts: Set<Int>) {
        var ids = Set<String>(), targets = Set<String>()
        var ports = Set<Int>()
        for line in text.split(separator: "\n") {
            if line.hasPrefix("ID\t") {
                let full = String(line.dropFirst(3))
                let id = full.split(separator: ":").last.map(String.init) ?? full
                if UUID(uuidString: id) != nil { ids.insert(id) }
            } else if line.hasPrefix("ARGV\t"), let target = attachedSession(words(String(line.dropFirst(5)))) {
                targets.insert(target)
            } else if line.hasPrefix("PORT\t"), let port = Int(line.dropFirst(5)), (1...65535).contains(port) {
                ports.insert(port)
            }
        }
        return (ids, targets, ports)
    }

    static func focusScript(ttys: Set<String>, ids: Set<String>) -> String {
        func list(_ values: Set<String>) -> String { "{" + values.sorted().map { "\"\(Opener.asq($0))\"" }.joined(separator: ",") + "}" }
        return """
        tell application "iTerm"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if (tty of s is in \(list(ttys))) or (unique ID of s is in \(list(ids))) then
                            select s
                            select t
                            select w
                            activate
                            return "focused"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return "not-found"
        """
    }

    /// Decode shell quoting only for legacy discovery. No evaluation occurs.
    static func words(_ value: String) -> [String] {
        var result: [String] = [], word = ""
        var quote: Character?, escaped = false, started = false
        for c in value {
            if escaped { word.append(c); escaped = false; started = true; continue }
            if c == "\\", quote != "'" { escaped = true; continue }
            if c == quote { quote = nil; continue }
            if quote == nil, c == "'" || c == "\"" { quote = c; started = true; continue }
            if quote == nil, c.isWhitespace {
                if started { result.append(word); word = ""; started = false }
            } else { word.append(c); started = true }
        }
        if started { result.append(word) }
        return result
    }

    static func attachedSession(_ arguments: [String]) -> String? {
        guard let attach = arguments.firstIndex(where: { ["attach", "attach-session", "a", "attach-session"].contains($0) }) else { return nil }
        let rest = arguments.dropFirst(attach + 1)
        guard let option = rest.firstIndex(of: "-t"), arguments.indices.contains(option + 1) else { return nil }
        return arguments[option + 1]
    }

    static func matchesRemote(arguments: [String], host: String, session: String) -> Bool {
        // Kernel argv preserves the entire remote command as one argument.
        // Limit expansion to the command arguments, preserving quoted names.
        guard arguments.prefix(3).contains(where: {
            ["ssh", "mosh", "mosh-bridged"].contains(URL(fileURLWithPath: $0).lastPathComponent)
        }), arguments.contains(host) else { return false }
        for arg in arguments {
            if attachedSession(words(arg)) == session { return true }
        }
        return attachedSession(arguments) == session
    }

    struct TerminalProcess {
        let pid: Int32
        let parentPID: Int32
        let tty: String
        let arguments: [String]
    }

    /// An interactive bridge's original command has no tmux session name.
    /// Its live carrier still names the exact remote Mosh server port. Anchor
    /// that carrier to its parent bridge's host, including LAN fallback commands.
    static func moshBridgeTTYs(_ processes: [TerminalProcess], host: String, ports: Set<Int>) -> Set<String> {
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var matches: [Int: Set<String>] = [:]
        for process in processes {
            let candidates = bridgeRemotePorts(process.arguments).intersection(ports)
            guard !candidates.isEmpty else { continue }
            var parent = process.parentPID
            var visited = Set<Int32>()
            while visited.count < 32, visited.insert(parent).inserted, let ancestor = byPID[parent] {
                if let target = bridgeHost(ancestor.arguments) {
                    if target == host, ancestor.tty == process.tty {
                        for port in candidates { matches[port, default: []].insert(process.tty) }
                    }
                    break
                }
                parent = ancestor.parentPID
            }
        }
        return matches.values.reduce(into: Set<String>()) { result, ttys in
            if ttys.count == 1 { result.formUnion(ttys) }
        }
    }

    static func bridgeHost(_ arguments: [String]) -> String? {
        guard let index = arguments.prefix(3).firstIndex(where: {
            URL(fileURLWithPath: $0).lastPathComponent == "mosh-bridged"
        }) else { return nil }
        return arguments.dropFirst(index + 1).first { !$0.hasPrefix("-") }
    }

    static func bridgeRemotePorts(_ arguments: [String]) -> Set<Int> {
        guard let index = arguments.prefix(3).firstIndex(where: {
            URL(fileURLWithPath: $0).lastPathComponent == "mosh-bridge"
        }), arguments.dropFirst(index + 1).first == "client" else { return [] }
        var ports = Set<Int>()
        var pending = Array(arguments.dropFirst(index + 1))
        // A carrier can contain a quoted `sh -c` LAN/fallback command, then a
        // quoted remote shell command. Decode syntax only; never evaluate it.
        for _ in 0..<4 {
            var nested: [String] = []
            for value in pending {
                let tokens = words(value)
                for offset in tokens.indices where offset + 2 < tokens.count {
                    if URL(fileURLWithPath: tokens[offset]).lastPathComponent == "mosh-bridge",
                       tokens[offset + 1] == "server",
                       let port = Int(tokens[offset + 2].trimmingCharacters(in: CharacterSet(charactersIn: ";"))),
                       (1...65535).contains(port) { ports.insert(port) }
                }
                if tokens != [value] { nested += tokens }
            }
            pending = nested
        }
        return ports
    }

    private static func terminalProcesses() -> [TerminalProcess] {
        let rows = run("/bin/ps", ["-axo", "pid=,ppid=,tty="]).output.split(separator: "\n")
        return rows.compactMap { row in
            let parts = row.split(whereSeparator: \.isWhitespace)
            guard parts.count == 3, let pid = Int32(parts[0]), let parent = Int32(parts[1]), parts[2] != "??" else { return nil }
            return TerminalProcess(pid: pid, parentPID: parent, tty: "/dev/" + parts[2], arguments: processArguments(pid))
        }
    }

    private static func processArguments(_ pid: Int32) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }
        let count = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        var offset = 4
        while offset < size, buffer[offset] != 0 { offset += 1 }
        while offset < size, buffer[offset] == 0 { offset += 1 }
        var args: [String] = []
        for _ in 0..<max(0, count) {
            let start = offset
            while offset < size, buffer[offset] != 0 { offset += 1 }
            args.append(String(decoding: buffer[start..<offset], as: UTF8.self))
            offset += 1
            if offset >= size { break }
        }
        return args
    }

    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 5) -> (output: String, status: Int32) {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return ("", -1) }
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()
        return (String(decoding: output, as: UTF8.self), process.terminationStatus)
    }
}
