#!/bin/zsh
# Build a signed scratch copy of the Mac app and screenshot task pages against the stand-in host.
#   mac_shot.sh build
#   mac_shot.sh shot <out.png> [--task <id>] [--edit] [--height N] [--width N]
# The bundle must be signed with the Developer ID and the real bundle id: an unsigned
# binary blocks forever on a keychain prompt inside SessionStore().
set -euo pipefail
REPO=/Users/eugenechan/dev/personal/lfg
OUT=${MAC_SHOT_DIR:-/private/tmp/claude-501/-Users-eugenechan-dev-personal-lfg/aa2af7c8-7d3f-4cc2-a9b8-df536e92c126/scratchpad/macapp}
APP=$OUT/lfg.app
HOST=${TASKS_HOST:-http://127.0.0.1:8932}

if [[ ${1:-} == build ]]; then
  mkdir -p "$APP/Contents/MacOS" "$OUT/mc"
  cp "$REPO/desktop/build/lfg.app/Contents/Info.plist" "$APP/Contents/" 2>/dev/null || true
  (cd "$REPO/desktop" && swiftc -Onone -parse-as-library -module-cache-path "$OUT/mc" -target arm64-apple-macosx26.0 \
    -o "$APP/Contents/MacOS/lfg" LFGSessions.swift ScheduledTasksPane.swift ../shared/ScheduledTasksView.swift ../shared/Tasks/*.swift \
    ../ios/LFGCore/Sources/LFGCore/ScheduledTasks.swift ../ios/LFGCore/Sources/LFGCore/TaskPresentation.swift \
    ../ios/LFGCore/Sources/LFGCore/TaskDetailPresentation.swift ../ios/LFGCore/Sources/LFGCore/ScheduleDraft.swift \
    ../ios/LFGCore/Sources/LFGCore/ModelCatalog.swift ../ios/LFGCore/Sources/LFGCore/SessionEffort.swift \
    ../ios/LFGCore/Sources/LFGCore/HiddenDirs.swift 2>&1 | grep -E "error" || true)
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/{print $2; exit}')
  codesign --force --timestamp=none --sign "$IDENTITY" "$APP" 2>&1 | grep -v "replacing existing" || true
  echo "built $APP"
  exit 0
fi

[[ ${1:-} == shot ]] || { echo "usage: $0 build | shot <out.png> [--task id] [--edit] [--height N] [--width N]"; exit 1; }
out=$2; shift 2
width=400; extra=()
while (( $# )); do
  case $1 in
    --width) width=$2; shift 2;;
    --task) extra+=(--task "00000000-0000-4000-8000-0000000000$2"); shift 2;;
    *) extra+=($1); shift;;
  esac
done
# Never launch the bundle through `open`: LaunchServices makes the app the screencapture's
# responsible process, which raises a Screen Recording prompt and a keychain prompt on Eugene's
# screen. Run from the shell, the window cannot become key, so toolbar buttons and traffic
# lights draw in their inactive (grey) style — a capture limit, not an app state.
timeout 60 "$APP/Contents/MacOS/lfg" --window-shot "$width" "$out" --tasks-host "$HOST" "${extra[@]}"
