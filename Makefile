# Theo – common tasks. The Xcode project is generated from project.yml (never committed).
SHELL := /bin/bash
DERIVED := build
XCBEAUTIFY := $(shell command -v xcbeautify || echo cat)

.PHONY: generate open test build-ios build-watch build-mac build icons clean

generate:
	scripts/ci/xcodegen.sh generate

open: generate
	open Theo.xcodeproj

## Unit tests for the platform-independent logic (Packages/TheoCore).
test:
	swift test --package-path Packages/TheoCore

build-ios: generate
	set -o pipefail && xcodebuild -project Theo.xcodeproj -scheme Theo -configuration Debug \
		-destination 'generic/platform=iOS Simulator' -derivedDataPath $(DERIVED) \
		CODE_SIGNING_ALLOWED=NO build 2>&1 | tee ios-build.log | $(XCBEAUTIFY)

## The iOS build also builds the embedded watch app; this builds only the watch app.
build-watch: generate
	set -o pipefail && xcodebuild -project Theo.xcodeproj -scheme TheoWatch -configuration Debug \
		-destination 'generic/platform=watchOS Simulator' -derivedDataPath $(DERIVED) \
		CODE_SIGNING_ALLOWED=NO build 2>&1 | tee watch-build.log | $(XCBEAUTIFY)

build-mac: generate
	set -o pipefail && xcodebuild -project Theo.xcodeproj -scheme TheoMac -configuration Debug \
		-destination 'generic/platform=macOS' -derivedDataPath $(DERIVED) \
		CODE_SIGNING_ALLOWED=NO build 2>&1 | tee mac-build.log | $(XCBEAUTIFY)

build: build-mac build-ios

## Regenerates every app icon PNG from docs/icon.
icons:
	docs/icon/export.sh

clean:
	rm -rf $(DERIVED) Theo.xcodeproj .build Packages/TheoCore/.build
