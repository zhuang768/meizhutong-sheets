#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-16.4.0.app/Contents/Developer}"
xcodegen generate
xcodebuild -scheme YouthAISubsidy \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  test
