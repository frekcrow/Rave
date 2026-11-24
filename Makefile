SDK := $(shell xcrun --sdk iphoneos --show-sdk-path)
CC := xcrun --sdk iphoneos clang

TARGET := build/RaveFix.dylib
SRC := src/Tweak.m

CFLAGS := -arch arm64 -isysroot $(SDK) -miphoneos-version-min=15.0 -fobjc-arc -Wall -Wextra -O2
LDFLAGS := -dynamiclib -install_name @rpath/RaveFix.dylib -framework Foundation

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SRC)
	@mkdir -p build
	$(CC) $(CFLAGS) $(LDFLAGS) $(SRC) -o $(TARGET)

clean:
	rm -rf build
