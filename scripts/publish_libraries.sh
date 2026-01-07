#!/usr/bin/env bash
set -euo pipefail

# Script to publish Snag libraries for Android (Maven Central) and iOS (SPM/CocoaPods)
# Usage: ./scripts/publish_libraries.sh <version>

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 1.0.6"
    exit 1
fi

NEW_VERSION=$1
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "🚀 Starting publishing process for version: $NEW_VERSION"

# 1. Update Android version in build.gradle.kts
echo "📝 Updating version in android/snag/build.gradle.kts..."
sed -i '' "s/coordinates(\"io.github.thanhcuong1990\", \"snag\", \".*\")/coordinates(\"io.github.thanhcuong1990\", \"snag\", \"$NEW_VERSION\")/g" "$ROOT_DIR/android/snag/build.gradle.kts"

# 2. Update iOS version in Snag.podspec
echo "📝 Updating version in Snag.podspec..."
sed -i '' "s/s.version          = '.*'/s.version          = '$NEW_VERSION'/g" "$ROOT_DIR/Snag.podspec"

# 3. Update version in README.md
echo "📝 Updating version in README.md..."
# Android dependency
sed -i '' "s/implementation 'io.github.thanhcuong1990:snag:.*'/implementation 'io.github.thanhcuong1990:snag:$NEW_VERSION'/g" "$ROOT_DIR/README.md"
# CocoaPods dependency
sed -i '' "s/pod 'Snag', '~> .*'/pod 'Snag', '~> $NEW_VERSION'/g" "$ROOT_DIR/README.md"

# 4. Update version in android/publishing.md
echo "📝 Updating version in android/publishing.md..."
sed -i '' "s/io.github.thanhcuong1990:snag:.*\"/io.github.thanhcuong1990:snag:$NEW_VERSION\"/g" "$ROOT_DIR/android/publishing.md"
sed -i '' "s/snag\/.*\/\"/snag\/$NEW_VERSION\/\"/g" "$ROOT_DIR/android/publishing.md"
# Handle the path without quotes if any
sed -i '' "s/snag\/[0-9]*\.[0-9]*\.[0-9]*\//snag\/$NEW_VERSION\//g" "$ROOT_DIR/android/publishing.md"

# 5. Git Commit and Tag
echo "💾 Committing version changes..."
git add "$ROOT_DIR/android/snag/build.gradle.kts" \
        "$ROOT_DIR/Snag.podspec" \
        "$ROOT_DIR/README.md" \
        "$ROOT_DIR/android/publishing.md"

git commit -m "chore: bump version to $NEW_VERSION"
git tag -a "v$NEW_VERSION" -m "Release v$NEW_VERSION"

# 6. Push to Remote
echo "🔄 Pushing changes and tags to origin..."
git push origin main
git push origin "v$NEW_VERSION"

echo "✅ Successfully prepared release v$NEW_VERSION!"
echo "🚀 The GitHub Actions CI/CD pipeline will now build the Mac App and publish the Android/iOS libraries."
echo "🔗 Monitor progress here: https://github.com/thanhcuong1990/Snag/actions"
