# tepevësen — shortcuts. Xcode is the primary way to build; these are here so
# you can check the project from a terminal without opening it.

PROJECT := tepevesen.xcodeproj
SCHEME  := tepevesen
SIM     := platform=iOS Simulator,name=iPhone 16

.PHONY: help open build sim clean icon project doctor

help:
	@echo "make open      open the project in Xcode"
	@echo "make build     compile for the simulator (no signing needed)"
	@echo "make sim       build and launch in the iPhone 16 simulator"
	@echo "make clean     delete build products"
	@echo "make icon      regenerate the app icon png"
	@echo "make project   regenerate the xcodeproj from project.yml (needs xcodegen)"
	@echo "make doctor    print toolchain versions and available simulators"

open:
	open $(PROJECT)

# Signing off: this proves the code compiles without needing a team.
build:
	xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'generic/platform=iOS Simulator' \
		-configuration Debug \
		CODE_SIGNING_ALLOWED=NO \
		CODE_SIGNING_REQUIRED=NO

sim:
	xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(SIM)' \
		-configuration Debug \
		CODE_SIGNING_ALLOWED=NO
	@echo "built. run it with: open -a Simulator && xcrun simctl install booted \\"
	@echo "  \"$$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) -showBuildSettings -destination '$(SIM)' | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $$2}')/$(SCHEME).app\""

clean:
	xcodebuild clean -project $(PROJECT) -scheme $(SCHEME)
	rm -rf build

icon:
	python3 Tools/make_icon.py

project:
	xcodegen generate

doctor:
	@xcodebuild -version
	@swift --version
	@echo "--- simulators ---"
	@xcrun simctl list devices available | grep -E "iPhone" || true
