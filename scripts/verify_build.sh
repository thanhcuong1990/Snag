#!/bin/bash
set -euo pipefail

# =============================================================================
# verify_build.sh — Build diagnostics for AI / CI pre-release gate
#
# Builds macOS app, iOS SPM library, and Android AAR library.
# Fails (exit 1) on any compiler error or warning.
# Usage:
#   ./scripts/verify_build.sh          # run all three
#   ./scripts/verify_build.sh mac      # run one target
#   ./scripts/verify_build.sh ios
#   ./scripts/verify_build.sh android
# =============================================================================

BLUE='\033[1;34m'; GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
step()    { echo -e "\n${BLUE}▶ $1${NC}"; }
success() { echo -e "${GREEN}✓ $1${NC}"; }
warn()    { echo -e "${YELLOW}⚠ $1${NC}"; }
fail()    { echo -e "${RED}✗ $1${NC}"; exit 1; }

REPO_ROOT=$(git rev-parse --show-toplevel)
TARGETS="${1:-all}"

OVERALL_PASS=true

# -----------------------------------------------------------------------------
# helpers
# -----------------------------------------------------------------------------

# xcodebuild outputs build log; we capture it, then scan for warnings/errors.
# Only count diagnostics attributed to a source file (file.swift:line:col: error|warning:),
# not Apple tool runtime messages like "appintentsmetadataprocessor[…] warning: …".
#
# SnagIdentityManager creates an app-private, isolated keychain so the local
# network debugger's self-signed TLS identity can be used without a keychain
# prompt on ad-hoc-signed (no Developer ID) builds. That requires the legacy
# SecKeychain* APIs — the modern SecItem/data-protection keychain can't create
# an isolated keychain and is subject to the same prompts. These deprecations
# are unavoidable and intentional, so allowlist them; every other diagnostic
# still fails the gate.
XCODE_ALLOWED_DIAGS="SecKeychain is deprecated"

check_xcode_log() {
    local log="$1"
    local label="$2"

    local errors warnings
    errors=$(grep -E "^/.*:[0-9]+:[0-9]+: error:" "$log" 2>/dev/null | grep -vE "$XCODE_ALLOWED_DIAGS" | grep -c "" || true)
    warnings=$(grep -E "^/.*:[0-9]+:[0-9]+: warning:" "$log" 2>/dev/null | grep -vE "$XCODE_ALLOWED_DIAGS" | grep -c "" || true)

    if [ "$errors" -gt 0 ]; then
        echo ""
        grep -E "^/.*:[0-9]+:[0-9]+: error:" "$log" | grep -vE "$XCODE_ALLOWED_DIAGS" | head -20
        fail "$label: $errors error(s) found"
    fi
    if [ "$warnings" -gt 0 ]; then
        echo ""
        grep -E "^/.*:[0-9]+:[0-9]+: warning:" "$log" | grep -vE "$XCODE_ALLOWED_DIAGS" | head -30
        fail "$label: $warnings warning(s) found — fix all warnings before release"
    fi
}

# Gradle captures stderr; parse for errors and warnings.
check_gradle_log() {
    local log="$1"
    local label="$2"

    local errors warnings
    errors=$(grep -cE "^(e|error):" "$log" 2>/dev/null || true)
    warnings=$(grep -cE "^(w|warning):" "$log" 2>/dev/null || true)

    if [ "$errors" -gt 0 ]; then
        echo ""
        grep -E "^(e|error):" "$log" | head -20
        fail "$label: $errors Kotlin error(s) found"
    fi
    if [ "$warnings" -gt 0 ]; then
        echo ""
        grep -E "^(w|warning):" "$log" | head -30
        fail "$label: $warnings Kotlin warning(s) found — fix all warnings before release"
    fi
}

# -----------------------------------------------------------------------------
# macOS
# -----------------------------------------------------------------------------
build_mac() {
    step "macOS app (Snag.xcodeproj)"
    local log
    log=$(mktemp /tmp/snag_mac_build.XXXXXX)

    set +e
    xcodebuild \
        -project "$REPO_ROOT/mac/Snag.xcodeproj" \
        -scheme Snag \
        -configuration Debug \
        -destination "platform=macOS" \
        -parallelizeTargets \
        OTHER_SWIFT_FLAGS="-warnings-as-errors -Wwarning DeprecatedDeclaration" \
        build 2>&1 | tee "$log" | xcbeautify --renderer terminal
    local xc_status=${PIPESTATUS[0]}
    set -e

    if [ "$xc_status" -ne 0 ]; then
        echo ""
        grep -E "error:" "$log" | head -20 || true
        fail "macOS: xcodebuild exited with status $xc_status"
    fi
    check_xcode_log "$log" "macOS"
    rm -f "$log"
    success "macOS build clean"
}

# -----------------------------------------------------------------------------
# iOS SPM library
# -----------------------------------------------------------------------------
build_ios() {
    step "iOS library (Swift Package)"
    local log
    log=$(mktemp /tmp/snag_ios_build.XXXXXX)

    # Pick a booted simulator if available, else fall back to any iPhone 16.
    local destination
    local booted
    booted=$(xcrun simctl list devices | grep "iPhone.*Booted" | head -1 | grep -oE '[A-F0-9-]{36}' || true)
    if [ -n "$booted" ]; then
        destination="platform=iOS Simulator,id=$booted"
    else
        destination="platform=iOS Simulator,name=iPhone 16"
    fi

    set +e
    xcodebuild \
        -scheme Snag \
        -destination "$destination" \
        -configuration Debug \
        OTHER_SWIFT_FLAGS="-warnings-as-errors" \
        build 2>&1 | tee "$log" | xcbeautify --renderer terminal
    local xc_status=${PIPESTATUS[0]}
    set -e

    if [ "$xc_status" -ne 0 ]; then
        echo ""
        grep -E "error:" "$log" | head -20 || true
        fail "iOS: xcodebuild exited with status $xc_status"
    fi
    check_xcode_log "$log" "iOS"
    rm -f "$log"
    success "iOS library build clean"
}

# -----------------------------------------------------------------------------
# Android AAR library
# -----------------------------------------------------------------------------
build_android() {
    step "Android library (:snag assembleDebug)"
    local log
    log=$(mktemp /tmp/snag_android_build.XXXXXX)

    cd "$REPO_ROOT/android"
    ./gradlew :snag:assembleDebug \
        --warning-mode all \
        -Pkotlin.options.warnings.enabled=true \
        2>&1 | tee "$log"

    # Gradle build failure is caught by set -e; check Kotlin diagnostics separately.
    check_gradle_log "$log" "Android"
    cd "$REPO_ROOT"
    rm -f "$log"
    success "Android library build clean"
}

# -----------------------------------------------------------------------------
# main
# -----------------------------------------------------------------------------
echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Snag Build Verification Gate     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"

case "$TARGETS" in
    mac)     build_mac ;;
    ios)     build_ios ;;
    android) build_android ;;
    all)
        build_mac
        build_ios
        build_android
        ;;
    *)
        fail "Unknown target '$TARGETS'. Use: mac | ios | android | all"
        ;;
esac

echo ""
echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   All builds passed — safe to ship   ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
