#!/bin/bash
# Build libghostty-internal.a from Ghostty source for Kanbango embedding.
#
# Prerequisites:
#   - macOS with Xcode (xcode-select --install)
#   - Zig compiler (install via: brew install zig)
#
# Usage:
#   ./scripts/build-ghostty-lib.sh                        # auto-detect or clone Ghostty
#   ./scripts/build-ghostty-lib.sh --ghostty-path /path   # use existing checkout
#   GHOSTTY_SRC=/path ./scripts/build-ghostty-lib.sh      # via env var
#
# On success, outputs libghostty-internal.a to the Kanbango project root.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KANBANGO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GHOSTTY_SRC="${GHOSTTY_SRC:-}"

# ── Parse args ──────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ghostty-path)
            GHOSTTY_SRC="$2"; shift 2 ;;
        --help)
            head -20 "$0"; exit 0 ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

# ── Find or clone Ghostty source ────────────────────────────────
if [[ -z "$GHOSTTY_SRC" ]]; then
    for dir in \
        "$KANBANGO_DIR/ghostty" \
        "$KANBANGO_DIR/../ghostty" \
        "$HOME/Documents/ghostty-main" \
        "$HOME/Documents/ghostty"
    do
        if [[ -f "$dir/build.zig" ]]; then
            GHOSTTY_SRC="$dir"
            break
        fi
    done
fi

if [[ -z "$GHOSTTY_SRC" ]]; then
    echo "Ghostty source not found. Cloning to $KANBANGO_DIR/ghostty ..."
    git clone --depth 1 https://github.com/ghostty-org/ghostty.git "$KANBANGO_DIR/ghostty"
    GHOSTTY_SRC="$KANBANGO_DIR/ghostty"
fi

echo "Using Ghostty source: $GHOSTTY_SRC"

# ── Check prerequisites ─────────────────────────────────────────
if ! command -v zig &>/dev/null; then
    echo "Error: 'zig' not found. Install it: brew install zig"
    echo "       Or download from: https://ziglang.org/download/"
    exit 1
fi

if ! xcode-select -p &>/dev/null; then
    echo "Error: Xcode command line tools not found."
    echo "       Run: xcode-select --install"
    exit 1
fi

# ── Build ───────────────────────────────────────────────────────
echo ""
echo "Building Ghostty xcframework (this will download deps on first run)..."
cd "$GHOSTTY_SRC"
zig build -Demit-xcframework 2>&1

# ── Copy result ─────────────────────────────────────────────────
XCFW_LIB="$GHOSTTY_SRC/macos/GhosttyKit.xcframework/macos-arm64_x86_64/ghostty-internal.a"
if [[ ! -f "$XCFW_LIB" ]]; then
    echo "Error: expected output not found at:"
    echo "  $XCFW_LIB"
    exit 1
fi

cp "$XCFW_LIB" "$KANBANGO_DIR/libghostty-internal.a"
echo ""
echo "Done → copied to $KANBANGO_DIR/libghostty-internal.a"
ls -lh "$KANBANGO_DIR/libghostty-internal.a"
