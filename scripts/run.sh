#!/bin/bash
set -e

# ==============================================================================
# Snag Example Runner Script
# 
# Best Practices:
# 1. set -e: Exit immediately if a command exits with a non-zero status.
# 2. Use relative paths from git root to ensure script works from anywhere.
# 3. Check for prerequisites (npm install, pod install) before running.
# 4. Use standard build tools (xcodebuild, gradlew) for consistency.
# ==============================================================================

# Colors for better visibility
BLUE='\033[1;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

function print_step() {
  echo -e "${BLUE}>>> $1${NC}"
}

function print_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

function print_error() {
  echo -e "${RED}ERROR: $1${NC}"
}

# Ensure we are at the root of the repo
REPO_ROOT=$(git rev-parse --show-toplevel)

MODE=$1

if [ -z "$MODE" ]; then
  echo "Usage: ./scripts/run.sh [command]"
  echo ""
  echo "Commands:"
  echo "  ios           Build the Native iOS Example (scheme: example)"
  echo "  android       Build and install the Native Android Example"
  echo "  rn-ios        Run the React Native Example on iOS"
  echo "  rn-android    Run the React Native Example on Android"
  echo "  mac           Open the Mac App in Xcode (scheme: Snag)"
  echo ""
  exit 1
fi

case $MODE in
  ios)
    print_step "Starting Native iOS Example Build..."
    cd "$REPO_ROOT/example/ios"
    
    # Best Practice: Check if a simulator is booted to avoid launching a random one
    # or failing if none are available.
    BOOTED_SIMULATOR=$(xcrun simctl list devices | grep "(Booted)" | head -n 1)
    
    if [ -z "$BOOTED_SIMULATOR" ]; then
        echo "No booted simulator found. Attempting to build for 'iPhone 16'..."
        DESTINATION="platform=iOS Simulator,name=iPhone 16"
    else
        echo "Found booted simulator: $BOOTED_SIMULATOR"
        # Extract UUID for precise targeting
        UUID=$(echo "$BOOTED_SIMULATOR" | grep -oE '[A-F0-9-]{36}')
        DESTINATION="platform=iOS Simulator,id=$UUID"
    fi
    
    print_step "Building 'example' scheme for destination: $DESTINATION"
    
    # Best Practice: Use -project if no workspace exists. Use -quiet to reduce noise, 
    # but strictly speaking, standard output helps debugging.
    # We use 'build' here. To run, normally you'd use 'test' (if tests exist) or external tools.
    # For local dev, checking the build passes is the first step.
    xcodebuild -project example.xcodeproj \
               -scheme example \
               -destination "$DESTINATION" \
               build
               
    print_success "Build Succeeded! To run the app:"
    echo "1. Open example/ios/example.xcodeproj in Xcode"
    echo "2. Select the simulator ($DESTINATION)"
    echo "3. Press Cmd+R"
    ;;

  android)
    print_step "Starting Native Android Example Build..."
    cd "$REPO_ROOT/example/android"
    
    # Best Practice: Ensure local.properties exists or handled by environment.
    # Assuming environment is set up (ANDROID_HOME).
    
    print_step "Installing Debug Variant..."
    ./gradlew installDebug
    
    # Best Practice: Launch the app automatically after install.
    # Package: com.snag
    # Activity: com.snag.snagandroid.ui.MainActivity
    print_step "Launching App..."
    adb shell am start -n com.snag/com.snag.snagandroid.ui.MainActivity
    
    print_success "Android App Launched."
    ;;

  rn-ios)
    print_step "Starting React Native iOS..."
    cd "$REPO_ROOT/example/react-native"
    
    # Best Practice: Ensure dependencies are installed
    if [ ! -d "node_modules" ]; then
        print_step "Installing Node dependencies..."
        npm install
    fi
    
    # Best Practice: Ensure Pods are synced
    print_step "Installing Pods..."
    cd ios && pod install && cd ..
    
    print_step "Running npx react-native run-ios..."
    npx react-native run-ios
    ;;

  rn-android)
    print_step "Starting React Native Android..."
    cd "$REPO_ROOT/example/react-native"
    
    if [ ! -d "node_modules" ]; then
         print_step "Installing Node dependencies..."
         npm install
    fi
    
    print_step "Running npx react-native run-android..."
    npx react-native run-android
    ;;

  mac)
    print_step "Opening Mac App..."
    cd "$REPO_ROOT/mac"
    
    # Since running a Mac app from CLI (launching the binary) is less common than
    # running via Xcode for debugging, we open the project.
    # But we can at least verify the build.
    
    print_step "Verifying Build (Snag scheme)..."
    xcodebuild -project Snag.xcodeproj \
               -scheme Snag \
               -destination "platform=macOS" \
               build
               
    print_success "Build Succeeded. Opening Xcode..."
    open Snag.xcodeproj
    ;;
    
  help|--help|-h)
    echo "Usage: ./scripts/run.sh [command]"
    echo ""
    echo "Commands:"
    echo "  ios           Build the Native iOS Example (scheme: example)"
    echo "  android       Build and install the Native Android Example"
    echo "  rn-ios        Run the React Native Example on iOS"
    echo "  rn-android    Run the React Native Example on Android"
    echo "  mac           Open the Mac App in Xcode (scheme: Snag)"
    echo ""
    ;;

  *)
    print_error "Unknown command: $MODE"
    echo "Run with 'help' to see usage."
    exit 1
    ;;
esac
