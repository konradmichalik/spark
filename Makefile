.PHONY: xcode build clean lint setup brand

xcode:
	xcodegen generate

build: xcode
	xcodebuild -scheme Spark -configuration Release build

# Swift: SwiftLint (auto-detect Xcode for SourceKit)
lint:
	@if [ -z "$$DEVELOPER_DIR" ] && [ -d /Applications/Xcode.app ]; then \
		DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftlint lint --strict; \
	else \
		swiftlint lint --strict; \
	fi

clean:
	rm -rf build/
	rm -rf DerivedData/
	rm -rf Spark.xcodeproj

# Regenerate app icon, README logo and website icons from the dot mark
brand:
	swift scripts/render-brand-assets.swift $(CURDIR)

setup:
	git config core.hooksPath .githooks
	brew install xcodegen swiftlint
