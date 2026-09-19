DEVELOPER_DIR ?= /Applications/Xcode-16.4.0.app/Contents/Developer
DESTINATION ?= platform=iOS Simulator,name=iPhone 16,OS=18.6
SCHEME ?= YouthAISubsidy

.PHONY: generate build test uitest format-check simulator-boot

generate:
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

format-check:
	@echo "Swift sources present:"
	@find YouthAISubsidy YouthAISubsidyTests YouthAISubsidyUITests -name "*.swift" | wc -l

simulator-boot:
	DEVELOPER_DIR="$(DEVELOPER_DIR)" xcrun simctl boot "iPhone 16" || true
	open -a Simulator
