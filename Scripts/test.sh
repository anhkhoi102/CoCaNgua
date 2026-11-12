#!/usr/bin/env bash
# Runs all unit tests through the Xcode scheme (same tests Xcode's ⌘U runs).
# Faster alternative for logic-only changes:
#   swift test --package-path Packages/CoCaNguaCore
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
xcodebuild -project CoCaNgua.xcodeproj -scheme CoCaNgua \
           -derivedDataPath build/DerivedData -destination 'platform=macOS,arch=arm64' test
