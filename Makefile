CXX := /usr/bin/clang++
CXXFLAGS := -std=c++20 -arch arm64 -O2 -Wall -Wextra -Wpedantic -Wno-deprecated-declarations
TARGET := .build/cs2-native-lab

.PHONY: all test
all: $(TARGET)

$(TARGET): src/main.cpp
	mkdir -p .build
	$(CXX) $(CXXFLAGS) $< -o $@

test: $(TARGET)
	CS2_NATIVE_LAB="$(CURDIR)/$(TARGET)" python3 -m unittest discover -s tests -v
