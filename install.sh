#!/usr/bin/env bash
# agent-familiar installer: checks prerequisites, pulls the embedding model,
# builds the anchor tables, and smoke-tests synthesis.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
WARN=0

say()  { printf '%s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; WARN=1; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

say "agent-familiar install"
say ""
say "Checking prerequisites..."

# --- python3 ---
if command -v python3 >/dev/null; then
  PYVER=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')
  python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' \
    && pass "python3 $PYVER" \
    || fail "python3 >= 3.10 required (found $PYVER)"
else
  fail "python3 not found. macOS: brew install python3 | Debian/Ubuntu: sudo apt install python3"
fi

# --- sox ---
if command -v sox >/dev/null; then
  pass "sox"
else
  fail "sox not found. macOS: brew install sox | Debian/Ubuntu: sudo apt install sox"
fi

# --- audio player ---
case "$(uname)" in
  Darwin)
    command -v afplay >/dev/null && pass "afplay" || fail "afplay missing (unexpected on macOS)"
    ;;
  *)
    if command -v paplay >/dev/null || command -v aplay >/dev/null || command -v ffplay >/dev/null; then
      pass "audio player ($(command -v paplay || command -v aplay || command -v ffplay))"
    else
      warn "no audio player found — install one of: pulseaudio-utils (paplay), alsa-utils (aplay), ffmpeg (ffplay)"
    fi
    ;;
esac

# --- ollama (optional but recommended) ---
EMBED_OK=0
if curl -s --max-time 2 http://localhost:11434/api/tags >/dev/null 2>&1; then
  if curl -s --max-time 2 http://localhost:11434/api/tags | grep -q all-minilm; then
    pass "ollama serving, all-minilm present"
    EMBED_OK=1
  elif command -v ollama >/dev/null; then
    say "  pulling all-minilm (46MB)..."
    ollama pull all-minilm && EMBED_OK=1 && pass "all-minilm pulled" \
      || warn "could not pull all-minilm"
  else
    warn "ollama serving but all-minilm missing and ollama CLI not found"
  fi
else
  warn "ollama not running — the familiar will use a cruder lexicon fallback.
    To enable embeddings later:
      macOS: brew install ollama && brew services start ollama
      Linux: curl -fsSL https://ollama.com/install.sh | sh
    then: ollama pull all-minilm && python3 $HERE/build_anchors.py"
fi

say ""
say "Building..."

# --- anchors (requires embeddings) ---
if [ "$EMBED_OK" = 1 ]; then
  (cd "$HERE" && python3 build_anchors.py >/dev/null) \
    && pass "affect axes + texture bank built" \
    || fail "build_anchors.py failed"
else
  warn "skipping anchor build (no embedder); rerun ./install.sh once ollama is up"
fi

# --- smoke test: render without playing ---
SMOKE=$(mktemp -t familiar-smoke)
if printf '%s' "all tests pass, shipped" \
   | (cd "$HERE" && python3 familiar.py render --mode creature --session install-smoke --out "$SMOKE") >/dev/null 2>&1 \
   && [ -s "$SMOKE" ]; then
  pass "synthesis smoke test (rendered $(du -h "$SMOKE" | cut -f1 | tr -d ' '))"
  rm -f "$SMOKE"
else
  fail "synthesis smoke test failed — run manually to see the error:
  echo test | python3 $HERE/familiar.py render --mode creature --out /tmp/t.wav"
fi

say ""
say "Hear it:"
say "  echo \"all tests pass, shipped to production\" | python3 $HERE/familiar.py play --mode creature"
say ""
say "Wire into Claude Code by merging this into the hooks section of ~/.claude/settings.json:"
say '  "Notification": [{ "matcher": "", "hooks": [{ "type": "command", "command": "'"$HERE"'/hook.sh" }] }],'
say '  "Stop":         [{ "matcher": "", "hooks": [{ "type": "command", "command": "'"$HERE"'/hook.sh" }] }]'
say ""
say "Then restart your Claude Code session. See README.md for configuration."
[ "$WARN" = 1 ] && say "(finished with warnings above)"
exit 0
