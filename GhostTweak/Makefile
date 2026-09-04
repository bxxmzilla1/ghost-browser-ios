# GhostTweak — arm64 dylib injected into sideloaded Instagram (Blaze-style)
SDK  := $(shell xcrun --sdk iphoneos --show-sdk-path)
CC   := xcrun -sdk iphoneos clang
OUT  := GhostTweak.dylib

CFLAGS := -arch arm64 \
	-isysroot $(SDK) \
	-miphoneos-version-min=15.0 \
	-fobjc-arc \
	-fmodules \
	-dynamiclib \
	-install_name @executable_path/Frameworks/$(OUT) \
	-Wno-deprecated-declarations

LDFLAGS := -framework Foundation -framework UIKit -framework CFNetwork -framework WebKit

SRCS := src/GhostTweak.m src/GhostTokenStore.m src/GhostHooks.m src/GhostSettings.m

.PHONY: all clean

all: $(OUT)

$(OUT): $(SRCS)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(SRCS)
	@file $@

clean:
	rm -f $(OUT)
