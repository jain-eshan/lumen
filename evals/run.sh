#!/bin/zsh
# Runs Lumen's Follow mode against a drawn stand-in for the Claude chat and checks what it would speak.
#   usage: evals/run.sh [path/to/Lumen.app] [scenario ...]     (default: /Applications/Lumen.app, every scenario)
# Nothing shows on screen and the cursor is not touched, so the computer stays usable. There is no sound and no
# Screen Recording is needed. It does use the Claude Code CLI to plan the reading, as the app does when Claude is connected.
# The page is drawn by app/Simulation.swift. Each scenario below is a failure that was reported from real use, so add
# a line there and a case in Simulation.swift when a new one turns up, and run this before every release.
#
#   name | page | chat column width | area read (chat column, or the whole window) | purpose | must be spoken | must not be spoken
REPLIES="Read only the replies from Claude."
SCENARIOS=(
  "long-reply|long|560|chat|$REPLIES|ENDMARKER,Bottom up|"
  "long-reply-everything-wide|long|400|all||ENDMARKER,Bottom up|"
  "long-reply-replies-wide|long|400|all|$REPLIES|ENDMARKER,Bottom up|"
  "own-message|usermsg|560|chat|$REPLIES|WAYPOINT|Zanzibar"
  "own-message-wide|usermsg|400|all|$REPLIES|WAYPOINT|Zanzibar"
  "short-reply|short|560|chat|$REPLIES|Go ahead|"
  "thinking-line|thinking|560|chat|$REPLIES|SIGNPOST|Checking whether"
)

APP=${1:-/Applications/Lumen.app}
[[ -x $APP/Contents/MacOS/Lumen ]] || { echo "No app at $APP"; exit 2 }
shift 2>/dev/null
WORK=$(mktemp -d)
trap 'pkill -f "$APP/Contents/MacOS/Lumen --simulate-screen" 2>/dev/null; rm -rf $WORK' EXIT

failed=0
for row in $SCENARIOS; do
  parts=("${(@s:|:)row}")
  name=$parts[1]; page=$parts[2]; chat=$parts[3]; area=$parts[4]; purpose=$parts[5]; must=$parts[6]; mustnot=$parts[7]
  (( $# > 0 )) && (( ${@[(Ie)$name]} == 0 )) && continue
  log=$WORK/$name.log
  "$APP/Contents/MacOS/Lumen" --simulate-screen=$page,$chat,$area --purpose="$purpose" --log-file=$log --log-spoken >/dev/null 2>&1 &
  pid=$!
  spoken() { grep "TEST spoke:" $log 2>/dev/null | sed 's/.*TEST spoke: //' }
  # Done when everything that must be spoken has been, or after two minutes.
  for i in {1..60}; do
    sleep 2
    ok=1; for marker in ${(s:,:)must}; do spoken | grep -q -- "$marker" || ok=0; done
    (( ok )) && break
  done
  # Text that must stay unread could still be on its way.
  [[ -n $mustnot ]] && sleep 10
  problems=()
  for marker in ${(s:,:)must}; do spoken | grep -q -- "$marker" || problems+=("never read \"$marker\""); done
  for marker in ${(s:,:)mustnot}; do spoken | grep -q -- "$marker" && problems+=("read \"$marker\" aloud"); done
  if (( ${#problems} )); then
    failed=1
    echo "FAIL  $name: ${(j:; :)problems}"
    spoken | sed 's/^/        spoke: /' | cut -c1-110
    grep -E "scrolled|reached the end|screen unchanged|guard|own message" $log 2>/dev/null | cut -c26-150 | sed 's/^/        log: /'
  else
    echo "PASS  $name"
  fi
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
done
exit $failed
