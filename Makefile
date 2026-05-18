PROJECT  := Crowy.xcodeproj
SCHEME   := Crowy
CONFIG   := Debug
DEST     := platform=macOS

BUILT_DIR = $(shell xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $$2}' | head -1)
APP       = $(BUILT_DIR)/$(SCHEME).app

.PHONY: build run dev clean config doctor help

help:
	@echo "Targets:"
	@echo "  make dev      - build then launch the app binary"
	@echo "  make build    - xcodebuild Debug for macOS"
	@echo "  make run      - launch the already-built app binary"
	@echo "  make clean    - xcodebuild clean"
	@echo "  make config   - regenerate buildServer.json (xcode-build-server)"
	@echo "  make doctor   - check required tools"

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -destination '$(DEST)' build

run:
	"$(APP)/Contents/MacOS/$(SCHEME)"

dev: build run

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) clean

config:
	xcode-build-server config -scheme $(SCHEME) -project $(PROJECT)

doctor:
	@echo "== Tools =="
	@command -v xcodebuild         >/dev/null && echo "ok  xcodebuild         ($$(xcodebuild -version | head -1))" || echo "MISS xcodebuild"
	@command -v xcode-build-server >/dev/null && echo "ok  xcode-build-server ($$(xcode-build-server --help 2>&1 | head -1))" || echo "MISS xcode-build-server  (brew install xcode-build-server)"
	@command -v xcrun              >/dev/null && echo "ok  xcrun" || echo "MISS xcrun"
	@command -v swift              >/dev/null && echo "ok  swift              ($$(swift --version | head -1))" || echo "MISS swift"
	@echo "== Project =="
	@test -d $(PROJECT)           && echo "ok  $(PROJECT)"     || echo "MISS $(PROJECT)"
	@test -f buildServer.json     && echo "ok  buildServer.json"     || echo "MISS buildServer.json  (run: make config)"
	@echo "== Build settings =="
	@echo "    BUILT_PRODUCTS_DIR = $(BUILT_DIR)"
	@test -d "$(BUILT_DIR)"       && echo "ok  build dir exists" || echo "warn build dir missing (run: make build)"
	@test -d "$(APP)"             && echo "ok  $(APP)" || echo "warn app not built yet"
