#!/bin/sh
# Checks both halves of the plug-in ↔ helper handshake without installing
# anything. Needs build.sh to have run. The helper answers only Apple's
# SecurityAgentHelper, so helper → real unlock is proven only on the lock screen;
# the plug-in's own allow/deny logic is fully exercised here.
set -u
here=$(cd "$(dirname "$0")" && pwd)
build="$here/../build"
sock_dir=/tmp/dev.omg.lfg-unlock
helper="$build/lfg-unlock"
fail=0
started=$(date "+%Y-%m-%d %H:%M:%S")

clang -fobjc-arc -framework Foundation -o "$build/plugin-harness" "$here/plugin-harness.m" || exit 1
harness() { "$build/plugin-harness" "$build/LFGUnlockPlugin.bundle"; }
check() { # name expected actual
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected '$2', got '$3'"; fail=1; fi
}

# 1. Nobody listening: the everyday case when a person unlocks. Must deny.
rm -rf "$sock_dir"
check "no helper running → deny" "result=deny" "$(harness)"

# A one-shot server that answers ALLOW: run_server <socket path>
run_server() {
/usr/bin/python3 - "$1" <<'EOF2' &
import os, socket, sys
p = sys.argv[1]
try: os.unlink(p)
except FileNotFoundError: pass
s = socket.socket(socket.AF_UNIX); s.bind(p); s.listen(1); s.settimeout(8)
try:
    c, _ = s.accept(); c.recv(32); c.sendall(b"ALLOW\n"); c.close()
except Exception: pass
os.unlink(p)
EOF2
}

# 2. A server owned by the console user that says ALLOW is trusted: that is the
#    documented boundary (anything running as the user can run the helper), and
#    it proves the plug-in's allow path end to end.
mkdir -p "$sock_dir" && chmod 755 "$sock_dir"
run_server "$sock_dir/unlock.sock"; sleep 1
check "console user's server says ALLOW → allow" "result=allow" "$(harness)"
wait

# 3. The socket directory swapped for a symlink (to a dir with a live socket): deny.
rm -rf "$sock_dir"; real=$(mktemp -d); ln -s "$real" "$sock_dir"
run_server "$real/unlock.sock"; sleep 1
check "symlinked socket directory → deny" "result=deny" "$(harness)"
wait; rm -f "$sock_dir"; rm -rf "$real"

# 4. The real helper: the plug-in must accept it as a peer, and the helper must
#    refuse the harness (not Apple-signed). Result: deny, with the refusal logged.
touch "$HOME/.lfg/unlock.log"; before=$(wc -l < "$HOME/.lfg/unlock.log")
"$helper" serve 4 2>/dev/null &
sleep 1
check "real helper, non-Apple asker → deny" "result=deny" "$(harness)"
wait
refused=$(tail -n +"$((before + 1))" "$HOME/.lfg/unlock.log" | grep -c "refused a socket peer that is not Apple-signed")
check "helper refused the non-Apple asker" "1" "$refused"

# 5. Plug-in log: the symlink was caught by the ownership check.
sleep 1
plog=$(log show --start "$started" --info --style compact --predicate 'subsystem == "dev.omg.lfg-unlock"' 2>/dev/null)
check "plug-in rejected the symlinked directory" "1" "$(echo "$plog" | grep -c 'socket directory is missing or not owned')"
check "plug-in saw no pending request in case 1" "1" "$(echo "$plog" | grep -c 'no unlock request pending')"

# 6. With the plug-in not installed, `unlock` must refuse before typing anything.
if ! "$helper" status | grep -q "plug-in: installed"; then
  "$helper" unlock 2>/dev/null; code=$?
  locked=$("$helper" status | head -1)
  if [ "$locked" = "screen: locked" ]; then
    check "unlock refuses without the plug-in (exit 2)" "2" "$code"
  else
    check "unlock on an unlocked screen is a no-op (exit 0)" "0" "$code"
  fi
fi

exit $fail
