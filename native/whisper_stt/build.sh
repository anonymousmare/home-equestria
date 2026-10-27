#!/usr/bin/env bash
# Builds whisper.cpp 1.8.3 as static libraries per platform, then this GDExtension (player board #13,
# 2026-10-26). whisper.cpp source: github.com/ggml-org/whisper.cpp tag v1.8.3, unpacked at $WHISPER_SRC.
#   WHISPER_SRC=~/tools/whisper-src/whisper.cpp-1.8.3 native/whisper_stt/build.sh [linux|windows|android ...]
set -euo pipefail
cd "$(dirname "$0")"
W="${WHISPER_SRC:?set WHISPER_SRC to the whisper.cpp 1.8.3 source folder}"
GODOT_CPP="${GODOT_CPP:-$HOME/tools/godot-cpp}"
SCONS="${SCONS:-$HOME/tools/scons-venv/bin/scons}"
ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
NDK_VERSION="${NDK_VERSION:-27.1.12297006}"
MINGW="${MINGW:-$HOME/tools/llvm-mingw-20260922-ucrt-ubuntu-22.04-x86_64}"
SCONS_LOCK="${SCONS_LOCK:-$HOME/project/captures/navigation-overhaul-2026-10-02/scons.lock}"
JOBS="${JOBS:-$(( $(nproc) / 2 ))}"
# No machine paths in shipped binaries.
PREFIX_MAP="-ffile-prefix-map=$HOME/=~/"
COMMON=(-G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DWHISPER_BUILD_EXAMPLES=OFF
	-DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=OFF -DGGML_OPENMP=OFF -DGGML_NATIVE=OFF
	-DCMAKE_POSITION_INDEPENDENT_CODE=ON "-DCMAKE_C_FLAGS=$PREFIX_MAP" "-DCMAKE_CXX_FLAGS=$PREFIX_MAP")

whisper() { # build folder, extra CMake arguments
	local dir="$W/$1"; shift
	cmake -S "$W" -B "$dir" "${COMMON[@]}" "$@" >/dev/null
	cmake --build "$dir" -j "$JOBS" --target whisper
}

extension() { # build folder, scons arguments
	local dir="$W/$1"; shift
	for target in template_debug template_release; do
		WHISPER_SRC="$W" WHISPER_BUILD="$dir" GODOT_CPP="$GODOT_CPP" ANDROID_HOME="$ANDROID_HOME" \
			flock "$SCONS_LOCK" nice -n 10 "$SCONS" -j "$JOBS" target="$target" "$@"
	done
}

for platform in "${@:-linux windows android}"; do
	for p in $platform; do
		case "$p" in
		linux)
			whisper build-linux-x86_64
			extension build-linux-x86_64 platform=linux ;;
		windows)
			whisper build-windows-x86_64 -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_SYSTEM_PROCESSOR=x86_64 \
				"-DCMAKE_C_COMPILER=$MINGW/bin/x86_64-w64-mingw32-clang" "-DCMAKE_CXX_COMPILER=$MINGW/bin/x86_64-w64-mingw32-clang++" \
				"-DCMAKE_RC_COMPILER=$MINGW/bin/x86_64-w64-mingw32-windres"
			extension build-windows-x86_64 platform=windows use_mingw=yes use_llvm=yes "mingw_prefix=$MINGW" arch=x86_64 ;;
		android)
			# Quest 2/3/Pro cores (Cortex-A78/X1 class) have dot-product and half-float instructions.
			whisper build-android-arm64 "-DCMAKE_TOOLCHAIN_FILE=$ANDROID_HOME/ndk/$NDK_VERSION/build/cmake/android.toolchain.cmake" \
				-DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-24 -DGGML_CPU_ARM_ARCH=armv8.2-a+dotprod+fp16
			# The Quest export only uses the release library (whisper_stt.gdextension).
			WHISPER_SRC="$W" WHISPER_BUILD="$W/build-android-arm64" GODOT_CPP="$GODOT_CPP" ANDROID_HOME="$ANDROID_HOME" \
				flock "$SCONS_LOCK" nice -n 10 "$SCONS" -j "$JOBS" target=template_release platform=android arch=arm64 "ndk_version=$NDK_VERSION" ;;
		*) echo "unknown platform $p" >&2; exit 1 ;;
		esac
	done
done
