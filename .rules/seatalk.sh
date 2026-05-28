# SeaTalk sticker constraints.
# Source: SeaTalk caps sticker uploads at 2MB per file.
# Recommended canvas: 320x320.
#
# Bytes use decimal MB (1 MB = 1,000,000 bytes) to match what macOS Finder,
# upload dialogs, and most chat apps display.

APP_NAME="SeaTalk"
MAX_SIZE_BYTES=$((2 * 1000 * 1000))

# GIF quality tiers, tried in order until output fits MAX_SIZE_BYTES.
# Format per line: "<fps> <width_px> <palette_colors>"
QUALITY_TIERS=(
    "15 320 256"
    "15 320 192"
    "12 320 128"
    "12 280 128"
    "10 240 96"
    "8  200 64"
    "6  180 48"
    "5  160 32"
)

# PNG downscale tiers (max width in px) for when the lossless image
# is too large at its native size.
PNG_QUALITY_TIERS=(320 280 240 200 160 140)
