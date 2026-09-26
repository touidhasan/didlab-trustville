#!/usr/bin/env bash
# Build the course site and push it to the `labsite` branch.
#
#   ./scripts/publish-labsite.sh
#
# The web host publishes files and does not build — the same rule dist/ follows. But a
# docs build is far more churn than a dApp build, so instead of committing it to main it
# goes to a branch of its own. main stays readable; the host pulls `labsite`.
#
# Then on the web host:  sudo lab-deploy
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRANCH=labsite
WORKTREE="$(mktemp -d)"

cleanup() { git -C "$ROOT" worktree remove --force "$WORKTREE" 2>/dev/null || true; rm -rf "$WORKTREE"; }
trap cleanup EXIT

cd "$ROOT"

command -v node >/dev/null || { echo "node is required"; exit 1; }
[ -d node_modules/vitepress ] || npm install

echo "==> building the course site"
npm run docs:build

DIST="$ROOT/docs/.vitepress/dist"
[ -f "$DIST/index.html" ] || { echo "build produced no index.html"; exit 1; }

echo "==> preparing the $BRANCH branch"
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git worktree add --force "$WORKTREE" "$BRANCH"
else
  # An orphan branch: the built site shares no history with the source, which is the
  # point — its diffs are noise and nobody should ever read them.
  git worktree add --force --detach "$WORKTREE"
  git -C "$WORKTREE" checkout --orphan "$BRANCH"
  git -C "$WORKTREE" rm -rf . >/dev/null 2>&1 || true
fi

find "$WORKTREE" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -r "$DIST/." "$WORKTREE/"
# Tell the host which commit of main this was built from, so a stale site is diagnosable.
git rev-parse --short HEAD > "$WORKTREE/BUILT_FROM"

cd "$WORKTREE"
git add -A
if git diff --cached --quiet; then
  echo "==> no change to publish"
  exit 0
fi
git commit -q -m "Course site built from $(cat BUILT_FROM)"
git push -q -f origin "$BRANCH"

echo "==> pushed $BRANCH (built from $(cat BUILT_FROM))"
echo "    now run 'sudo lab-deploy' on the web host"
