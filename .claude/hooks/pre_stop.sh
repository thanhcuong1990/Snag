#!/bin/bash
# pre_stop.sh — Claude Code Stop hook
#
# Detects which platforms have changed files and runs verify_build.sh for each.
# Exit 2  → block Claude from stopping (builds failed, feedback returned as context)
# Exit 0  → allow stop (all builds clean, or no relevant files changed)

REPO_ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)
if [ -z "$REPO_ROOT" ]; then exit 0; fi

VERIFY="$REPO_ROOT/scripts/verify_build.sh"
if [ ! -x "$VERIFY" ]; then exit 0; fi

# Files changed since last commit (staged + unstaged).
CHANGED=$(git -C "$REPO_ROOT" diff HEAD --name-only 2>/dev/null)
if [ -z "$CHANGED" ]; then exit 0; fi

# ── platform detection ──────────────────────────────────────────────────────
NEED_MAC=false; NEED_IOS=false; NEED_ANDROID=false

while IFS= read -r f; do
    case "$f" in
        mac/*)                           NEED_MAC=true ;;
        ios/*|Package.swift) NEED_IOS=true ;;
        android/*)                        NEED_ANDROID=true ;;
    esac
done <<< "$CHANGED"

$NEED_MAC     || $NEED_IOS     || $NEED_ANDROID || exit 0  # nothing relevant changed

# ── run builds ──────────────────────────────────────────────────────────────
FAILED=false

run() {
    local target="$1"
    echo "🔨 Verifying $target build..."
    if ! "$VERIFY" "$target" 2>&1; then
        echo "❌ $target build FAILED — fix errors/warnings before finishing."
        FAILED=true
    else
        echo "✅ $target build clean."
    fi
}

$NEED_MAC     && run mac
$NEED_IOS     && run ios
$NEED_ANDROID && run android

# ── result ──────────────────────────────────────────────────────────────────
if $FAILED; then
    echo ""
    echo "Build verification failed. Review the errors above, fix them, and try again."
    exit 2   # non-zero exit blocks Claude from stopping and feeds output back as context
fi

echo ""
echo "All builds verified clean — safe to stop."
exit 0
