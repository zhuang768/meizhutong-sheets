DEVELOPER_DIR ?= /Applications/Xcode-16.4.0.app/Contents/Developer
DESTINATION ?= platform=iOS Simulator,name=iPhone 16,OS=18.6
SCHEME ?= YouthAISubsidy

.PHONY: generate build test simulator-boot sheets-test sheets-generate sheets-app-batch

generate:
	@mkdir -p Config
	@test -f Config/Secrets.xcconfig || cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
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
	node scripts/tests/schema.test.js
	node scripts/tests/server.test.js
	node scripts/tests/ai-audit.test.js
	node scripts/generate/generate-app-batch-cases.js

sheets-generate:
	node scripts/generate/generate-volume-cases.js 50000

sheets-app-batch:
	node scripts/generate/generate-app-batch-cases.js
