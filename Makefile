DEVELOPER_DIR ?= /Applications/Xcode-16.4.0.app/Contents/Developer
DESTINATION ?= platform=iOS Simulator,name=iPhone 16,OS=18.6
SCHEME ?= YouthAISubsidy

.PHONY: generate build test simulator-boot sheets-test sheets-generate sheets-app-batch

generate:
	@mkdir -p Config
	@test -f Config/Secrets.xcconfig || cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
	@if [ -f Config/Secrets.xcconfig ] && [ ! -f Config/Secrets.local.xcconfig ]; then \
		grep -q '^API_CLIENT_KEY' Config/Secrets.xcconfig && cp Config/Secrets.xcconfig Config/Secrets.local.xcconfig || true; \
	fi
	xcodegen generate

build: generate
	DEVELOPER_DIR="$(DEVELOPER_DIR)" xcodebuild \
		-scheme "$(SCHEME)" \
		-destination "$(DESTINATION)" \
		-configuration Debug \
		CODE_SIGNING_ALLOWED=NO \
		build

test: generate
	DEVELOPER_DIR="$(DEVELOPER_DIR)" xcodebuild \
		-scheme "$(SCHEME)" \
		-destination "$(DESTINATION)" \
		-configuration Debug \
		CODE_SIGNING_ALLOWED=NO \
		test

simulator-boot:
	DEVELOPER_DIR="$(DEVELOPER_DIR)" xcrun simctl boot "iPhone 16" || true
	open -a Simulator

sheets-test:
	node scripts/schema.test.js
	node scripts/server.test.js
	node scripts/ai-audit.test.js
	node scripts/generate-app-batch-cases.js

sheets-generate:
	node scripts/generate-volume-cases.js 50000

sheets-app-batch:
	node scripts/generate-app-batch-cases.js
