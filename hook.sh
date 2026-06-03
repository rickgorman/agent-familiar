#!/bin/bash
# Claude Code adapter: speak the session's state as a short creature call.
# Reads the hook JSON on stdin, tails the transcript, plays. Fire-and-forget.
#
# Configuration (set in the environment, or inline in settings.json):
#   FAMILIAR_MODE    creature (default) | duet | vocab
#   FAMILIAR_DIR     where agent-familiar lives (default ~/.claude/agent-familiar)
#   FAMILIAR_VOLUME  0.0-1.0, default 0.35

FAMILIAR_DIR="${FAMILIAR_DIR:-$HOME/.claude/agent-familiar}"
PY=$(command -v python3 || echo /usr/bin/python3)

input=$(cat)
meta=$(printf '%s' "$input" | $PY -c '
import json, sys
d = json.load(sys.stdin)
print(d.get("transcript_path", ""))
print(d.get("session_id", "default"))
print(d.get("hook_event_name", ""))
' 2>/dev/null)

transcript=$(printf '%s' "$meta" | sed -n 1p)
session=$(printf '%s' "$meta" | sed -n 2p)
event=$(printf '%s' "$meta" | sed -n 3p)

[ -z "$transcript" ] && exit 0
[ -f "$transcript" ] || exit 0

text=$(tail -n 200 "$transcript" 2>/dev/null | $PY -c '
import json, sys
lines = []
for raw in sys.stdin:
    try:
        msg = json.loads(raw)
    except Exception:
        continue
    if msg.get("type") not in ("assistant", "user"):
        continue
    content = msg.get("message", {}).get("content")
    if isinstance(content, str):
        lines.append(content)
    elif isinstance(content, list):
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                lines.append(block["text"])
print("\n".join(lines)[-1000:])
')

[ -z "$text" ] && exit 0

need_args=()
if [ "$event" = "Notification" ]; then
  need_args=(--need halted)
fi

printf '%s' "$text" \
  | $PY "$FAMILIAR_DIR/familiar.py" play --mode "${FAMILIAR_MODE:-creature}" \
      --session "$session" "${need_args[@]}" \
  >/dev/null 2>&1 &
exit 0
