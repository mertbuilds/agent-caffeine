#!/usr/bin/env bash
# Nuke every cache and dependency dir, then reinstall. For when nothing makes sense.
# DRY_RUN=1 bash scripts/bad-day.sh  -> print what would be removed, touch nothing.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd -P)"

dry() { [[ "${DRY_RUN:-0}" == "1" ]]; }

# PIDs from `pgrep "$@"` whose working directory is inside this repo. Dev processes such
# as mprocs carry no repo path on their command line, so matching by command line
# alone would stop other checkouts' dev sessions too.
repo_pids() {
  local pid cwd
  for pid in $(pgrep "$@" 2>/dev/null); do
    cwd="$(readlink "/proc/$pid/cwd" 2>/dev/null || lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' || true)"
    if [[ "$cwd" == "$ROOT" || "$cwd" == "$ROOT/"* ]]; then
      echo "$pid"
    fi
  done
}

# pgrep/pkill patterns are extended regexes. Escape the path so a `.` in it matches
# only a dot, not a sibling checkout such as webXstarter next to web.starter.
ere_escape() { printf '%s' "$1" | sed 's/[[\.*^$?+(){|]/\\&/g'; }
ROOT_RE="$(ere_escape "$ROOT")"
PATTERNS=("$ROOT_RE/.*vite" "$ROOT_RE/.*storybook" "$ROOT_RE/.*/cf/bin/cf")

echo "» Stopping dev processes..."
PIDS="$(echo $(repo_pids -x mprocs))"
if ! dry; then
  if [[ -n "$PIDS" ]]; then
    kill $PIDS 2>/dev/null || true
  fi
  for pattern in "${PATTERNS[@]}"; do
    pkill -f "$pattern" 2>/dev/null || true
  done
else
  MATCHED="$(echo $(for pattern in "${PATTERNS[@]}"; do pgrep -f "$pattern" 2>/dev/null || true; done))"
  echo "  (dry run: would kill dev process pids [$PIDS] and vite/storybook/cf pids [$MATCHED] under $ROOT/)"
fi

echo "» Collecting removal targets..."
TARGETS=()
while IFS= read -r dir; do
  TARGETS+=("$dir")
done < <(find . -name node_modules -type d -prune -not -path './.git/*')

EXTRAS=(
  .turbo
  apps/web/.cloudflare
  apps/web/.output
  apps/web/.wrangler
  apps/web/src/paraglide
  packages/ui/storybook-static
  packages/ui/dist
)
for extra in "${EXTRAS[@]}"; do
  [[ -e "$extra" ]] && TARGETS+=("$extra")
done

WORKSPACES=(apps packages)
while IFS= read -r dir; do
  TARGETS+=("$dir")
done < <(find "${WORKSPACES[@]}" -maxdepth 3 -type d \( -name .vite -o -name .turbo \) -prune 2>/dev/null)

for t in "${TARGETS[@]}"; do
  if dry; then
    echo "  would remove: $t"
  else
    echo "  removing: $t"
    rm -rf "$t"
  fi
done

echo "» Pruning pnpm store..."
if dry; then
  echo "  (dry run: would run pnpm store prune)"
else
  pnpm store prune
fi

echo "» Reinstalling..."
if dry; then
  echo "  (dry run: would run pnpm install)"
else
  pnpm install
fi

echo "✓ Bad day handled."
