CXX := /usr/bin/clang++
CXXFLAGS := -std=c++20 -arch arm64 -O2 -Wall -Wextra -Wpedantic -Wno-deprecated-declarations
TARGET := .build/cs2-native-lab
APP := .build/CS2 en Mac.app
LAUNCHER := $(APP)/Contents/MacOS/cs2mac
INSTALL_DIR ?= $(HOME)/Applications

.PHONY: all test app test-app check install-app dist
all: app $(TARGET)

$(TARGET): src/main.cpp
	mkdir -p .build
	$(CXX) $(CXXFLAGS) $< -o $@

test: $(TARGET)
	CS2_NATIVE_LAB="$(CURDIR)/$(TARGET)" python3 -m unittest discover -s tests -v

app: macos/main.swift macos/Info.plist
	mkdir -p "$(APP)/Contents/MacOS"
	xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx13.0 macos/main.swift -o "$(LAUNCHER)" -framework AppKit -framework CryptoKit
	cp macos/Info.plist "$(APP)/Contents/Info.plist"
	mkdir -p "$(APP)/Contents/Resources"
	cp LICENSE THIRD_PARTY.md "$(APP)/Contents/Resources/"
	codesign --force --sign - "$(APP)"

test-app: app
	CS2MAC_LAUNCHER="$(CURDIR)/$(LAUNCHER)" python3 -m unittest discover -s tests -p 'test_launcher.py' -v

check: test test-app

install-app: app
	mkdir -p "$(INSTALL_DIR)"
	ditto "$(APP)" "$(INSTALL_DIR)/CS2 en Mac.app"

dist: app
	mkdir -p artifacts
	ditto -c -k --sequesterRsrc --keepParent "$(APP)" artifacts/CS2Mac-0.2.0-arm64.zip
