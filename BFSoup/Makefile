all: bff_noheads_main

FLAGS=-target x86_64-apple-macos13.6 -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX14.2.sdk -MMD -MT dependencies -x objective-c
METAL=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/metal
METALLIB=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/metallib


#FLAGS=-target x86_64-apple-macos13.6 -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX14.2.sdk -MMD -MT dependencies -x objective-c
#FLAGS=-target x86_64-apple-macos13.6 -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX14.2.sdk -MMD -MT dependencies -x c++
#METAL=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/metal
#METALLIB=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/metallib

#main: main.cc
bff_noheads_main: bff_noheads_main.m default.metallib
	clang++ ${FLAGS} -framework CoreGraphics -framework Foundation -framework Metal -o $@ $<

#%: %.m default.metallib
#	clang ${FLAGS} -framework CoreGraphics -framework Foundation -framework Metal -o $@ $@.m

%: %.m default.metallib
	clang ${FLAGS} -framework CoreGraphics -framework Foundation -framework Metal -o $@ $<

%: %.cc
	clang ${FLAGS} -framework CoreGraphics -framework Foundation -framework Metal -o $@ $<

%.air: %.metal
	#${METAL} -o $@ $<
	xcrun -sdk macosx metal -c $< -o $@

default.metallib: bff_noheads.air Shaders.air
	xcrun -sdk macosx metallib $^ -o $@
