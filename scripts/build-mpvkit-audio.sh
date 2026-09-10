#!/bin/bash
# Build Klopydrome's local audio-oriented MPVKit XCFramework.
#
# The fork keeps libmpv's client API and CoreAudio/AVFoundation outputs, while
# disabling GL, Vulkan/MoltenVK, hardware video decoding, the command-line
# player, Lua, Cocoa UI, disc devices, and libavdevice in its build scripts.
# FFmpeg is restricted to audio decoders, audio-capable demuxers, audio filters,
# and network protocols required for music streaming.
#
# The upstream tool produces static archives. This script links their local
# closure into a universal dynamic framework used by SwiftPM. libmpv 0.41.0
# still compiles dormant libplacebo video helpers; dynamic lookup leaves only
# their unreachable symbols unresolved instead of dragging video SDKs into the
# binary. The local C shim supplies the Vulkan entrypoint for an accidental probe.
#
# Requirements: Homebrew tools nasm, meson, ninja, cmake, pkg-config, wget, git.
# A clean arm64+x86_64 build takes roughly 30 to 60 minutes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MPVKIT_ROOT="$ROOT/vendor/MPVKit-Audio"
RELEASE_DIR="$MPVKIT_ROOT/dist/release"
XCFRAMEWORK_DIR="$RELEASE_DIR/xcframework"
FRAMEWORK="$MPVKIT_ROOT/dist/libmpv/macos/Libmpv.framework"

for tool in nasm meson ninja cmake pkg-config wget git xcodebuild xcrun zip; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'error: missing dependency: %s\n' "$tool" >&2
        exit 1
    fi
done

package_framework() {
    local sdk clang arch temp
    sdk="$(xcrun --sdk macosx --show-sdk-path)"
    clang="$(xcrun --sdk macosx --find clang)"
    temp="$(mktemp -d "${TMPDIR:-/tmp}/klopydrome-mpvkit.XXXXXX")"

    for arch in arm64 x86_64; do
        local archives=(
            "$MPVKIT_ROOT/dist/libmpv/macos/thin/$arch/lib/libmpv.a"
            "$MPVKIT_ROOT/dist/FFmpeg/macos/thin/$arch/lib/libavcodec.a"
            "$MPVKIT_ROOT/dist/FFmpeg/macos/thin/$arch/lib/libavfilter.a"
            "$MPVKIT_ROOT/dist/FFmpeg/macos/thin/$arch/lib/libavformat.a"
            "$MPVKIT_ROOT/dist/FFmpeg/macos/thin/$arch/lib/libavutil.a"
            "$MPVKIT_ROOT/dist/FFmpeg/macos/thin/$arch/lib/libswresample.a"
            "$MPVKIT_ROOT/dist/FFmpeg/macos/thin/$arch/lib/libswscale.a"
            "$MPVKIT_ROOT/dist/openssl/macos/thin/$arch/lib/libcrypto.a"
            "$MPVKIT_ROOT/dist/openssl/macos/thin/$arch/lib/libssl.a"
            "$MPVKIT_ROOT/dist/gmp/macos/thin/$arch/lib/libgmp.a"
            "$MPVKIT_ROOT/dist/nettle/macos/thin/$arch/lib/libhogweed.a"
            "$MPVKIT_ROOT/dist/nettle/macos/thin/$arch/lib/libnettle.a"
            "$MPVKIT_ROOT/dist/gnutls/macos/thin/$arch/lib/libgnutls.a"
            "$MPVKIT_ROOT/dist/libuchardet/macos/thin/$arch/lib/libuchardet.a"
            "$MPVKIT_ROOT/dist/libunibreak/macos/thin/$arch/lib/liblinebreak.a"
            "$MPVKIT_ROOT/dist/libunibreak/macos/thin/$arch/lib/libunibreak.a"
            "$MPVKIT_ROOT/dist/libfreetype/macos/thin/$arch/lib/libfreetype.a"
            "$MPVKIT_ROOT/dist/libfribidi/macos/thin/$arch/lib/libfribidi.a"
            "$MPVKIT_ROOT/dist/libharfbuzz/macos/thin/$arch/lib/libharfbuzz.a"
            "$MPVKIT_ROOT/dist/libass/macos/thin/$arch/lib/libass.a"
            "$MPVKIT_ROOT/dist/lcms2/macos/thin/$arch/lib/liblcms2.a"
            "$MPVKIT_ROOT/dist/libplacebo/macos/thin/$arch/lib/libplacebo.a"
        )
        for archive in "${archives[@]}"; do
            test -f "$archive" || {
                printf 'error: expected archive is missing: %s\n' "$archive" >&2
                rm -rf "$temp"
                exit 1
            }
        done

        "$clang" -dynamiclib -arch "$arch" -isysroot "$sdk" \
            -target "$arch-apple-macos12.0" -mmacosx-version-min=12.0 \
            -Wl,-u,_mpv_command -Wl,-u,_mpv_create -Wl,-u,_mpv_initialize \
            -Wl,-u,_mpv_observe_property -Wl,-u,_mpv_set_option_string \
            -Wl,-u,_mpv_set_property -Wl,-u,_mpv_set_wakeup_callback \
            -Wl,-u,_mpv_terminate_destroy -Wl,-u,_mpv_wait_event \
            -Wl,-dead_strip -Wl,-undefined,dynamic_lookup \
            -Wl,-install_name,@rpath/Libmpv.framework/Versions/A/Libmpv \
            "${archives[@]}" \
            -framework AVFoundation -framework AppKit -framework AudioToolbox \
            -framework Carbon -framework CoreAudio -framework CoreFoundation \
            -framework CoreGraphics -framework CoreMedia -framework CoreServices \
            -framework CoreText -framework CoreVideo -framework Foundation \
            -framework IOKit -framework MediaPlayer -framework Security \
            -framework VideoToolbox -lc++ -lbz2 -liconv -lz \
            -o "$temp/Libmpv-$arch"
    done

    lipo -create "$temp/Libmpv-arm64" "$temp/Libmpv-x86_64" \
        -output "$temp/Libmpv"
    install_name_tool -id '@rpath/Libmpv.framework/Versions/A/Libmpv' "$temp/Libmpv"
    cp "$temp/Libmpv" "$FRAMEWORK/Versions/A/Libmpv"
    chmod +x "$FRAMEWORK/Versions/A/Libmpv"
    rm -rf "$XCFRAMEWORK_DIR/Libmpv.xcframework"
    xcodebuild -create-xcframework -framework "$FRAMEWORK" \
        -output "$XCFRAMEWORK_DIR/Libmpv.xcframework"
    rm -f "$RELEASE_DIR/Libmpv.xcframework.zip"
    (
        cd "$XCFRAMEWORK_DIR"
        zip -qry "$RELEASE_DIR/Libmpv.xcframework.zip" Libmpv.xcframework
    )
    rm -rf "$temp"
}

case "${1:-}" in
    "")
        if [ -f "$FRAMEWORK/Versions/A/Libmpv" ] && [ -d "$XCFRAMEWORK_DIR/Libmpv.xcframework" ] && [ -f "$RELEASE_DIR/Libmpv.xcframework.zip" ]; then
            echo "==> Artifacts already present ($FRAMEWORK, $XCFRAMEWORK_DIR/Libmpv.xcframework) — skip build. Use --package-only to repackage."
            exit 0
        fi
        echo "==> Building audio-only MPVKit (arm64 + x86_64)..."
        (cd "$MPVKIT_ROOT" && swift run --build-path ./.build --package-path Sources/BuildScripts build platform=macos version=0.1.0-audio)
        ;;
    --package-only)
        echo "==> Repackaging existing audio-only archives..."
        ;;
    *)
        echo "usage: $0 [--package-only]" >&2
        exit 2
        ;;
esac

echo "==> Linking local Libmpv.framework..."
package_framework
echo "==> Done: $XCFRAMEWORK_DIR/Libmpv.xcframework"
