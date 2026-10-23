#!/usr/bin/env bash
# Smoke-test the built web Worker before it ships. Serves the output of
# `pnpm --filter @caffeinagent/web build` with the production preview and
# requires HTTP 200 and a <title> that starts with the app name for each page, or exits 1.
# The pages render without the api or the Worker's secrets, so CI needs neither.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${SMOKE_PORT:-4173}"
BASE="http://localhost:$PORT"
PAGES=(/)
EXPECT='<title>Agent Caffeine'
LOG="$(mktemp)"
BODY="$(mktemp)"

if curl -s -o /dev/null --max-time 2 "$BASE/"; then
  echo "smoke: something already answers on $BASE"
  exit 1
fi

# Job control puts the server in its own process group, so the cleanup also
# stops the vite and workerd processes that pnpm starts under it. Vite reads
# stdin for its shortcuts on a TTY, which stops a background job, hence </dev/null.
set -m
cd "$ROOT/apps/web"
pnpm exec vite preview --port "$PORT" --strictPort </dev/null >"$LOG" 2>&1 &
server=$!
cleanup() {
  kill -TERM -- "-$server" 2>/dev/null || true
  wait "$server" 2>/dev/null || true
  rm -f "$LOG" "$BODY"
}
trap cleanup EXIT

fail() {
  echo "smoke: $1"
  echo "--- preview log ---"
  tail -n 80 "$LOG"
  exit 1
}

ready=0
for _ in $(seq 1 60); do
  kill -0 "$server" 2>/dev/null || fail "preview exited before answering"
  if curl -s -o /dev/null --max-time 2 "$BASE/"; then
    ready=1
    break
  fi
  sleep 1
done
[[ $ready -eq 1 ]] || fail "preview did not answer on $BASE within 60 seconds"

failed=0
for page in "${PAGES[@]}"; do
  status="$(curl -s -o "$BODY" -w '%{http_code}' --max-time 30 "$BASE$page" || true)"
  if [[ "$status" == 200 ]] && grep -qF "$EXPECT" "$BODY"; then
    echo "smoke: $page ok"
  else
    echo "smoke: $page answered $status without '$EXPECT'"
    failed=1
  fi
done
[[ $failed -eq 0 ]] || fail "the built site does not render"
