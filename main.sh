#!/bin/bash

# Sticker conversion pipeline with pluggable per-app rules.
# Drop a config into ./rules/<name>.sh and run `./main.sh --app <name>`.
# Defaults to seatalk.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---------- Argument parsing ----------
APP="seatalk"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --app)    APP="$2"; shift 2 ;;
        --app=*)  APP="${1#*=}"; shift ;;
        --list)
            echo "Available rule sets:"
            for r in "$SCRIPT_DIR"/rules/*.sh; do
                [[ -f "$r" ]] && echo "  - $(basename "${r%.sh}")"
            done
            exit 0
            ;;
        -h|--help)
            cat <<EOF
Usage: $(basename "$0") [--app <name>] [--list] [--help]

Converts videos to GIF and images to PNG, enforcing per-app size limits
via iterative compression.

Options:
  --app <name>   Rule set to apply (default: seatalk)
  --list         List available rule sets
  -h, --help     Show this help

Add new apps by creating ./rules/<name>.sh defining MAX_SIZE_BYTES,
QUALITY_TIERS, and PNG_QUALITY_TIERS.
EOF
            exit 0
            ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

RULE_FILE="$SCRIPT_DIR/rules/${APP}.sh"
if [[ ! -f "$RULE_FILE" ]]; then
    echo "Rule file not found: $RULE_FILE" >&2
    echo "Run with --list to see available rule sets." >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$RULE_FILE"

if [[ -z "${MAX_SIZE_BYTES:-}" ]] || [[ ${#QUALITY_TIERS[@]} -eq 0 ]] || [[ ${#PNG_QUALITY_TIERS[@]} -eq 0 ]]; then
    echo "Rule '$APP' is missing MAX_SIZE_BYTES / QUALITY_TIERS / PNG_QUALITY_TIERS." >&2
    exit 1
fi

# ---------- Setup ----------
mkdir -p output input
[[ -f .output_counter ]] || echo "1" > .output_counter

# ---------- Helpers ----------
file_size() { stat -f%z "$1" 2>/dev/null || stat -c%s "$1"; }

human_size() {
    awk -v b="$1" 'BEGIN{
        if (b >= 1048576)      printf "%.2fMB", b/1048576
        else if (b >= 1024)    printf "%.0fKB", b/1024
        else                   printf "%dB", b
    }'
}

get_next_counter() {
    local current
    current=$(cat .output_counter)
    echo "$current"
    echo $((current + 1)) > .output_counter
}

# ---------- GIF conversion ----------
build_gif() {
    # build_gif <input> <output> <fps> <width> <colors>
    local input="$1" output="$2" fps="$3" width="$4" colors="$5"
    ffmpeg -loglevel error -i "$input" \
        -vf "fps=$fps,scale=$width:-1:flags=lanczos,palettegen=max_colors=$colors" \
        -y "/tmp/palette.png" || return 1
    ffmpeg -loglevel error -i "$input" -i "/tmp/palette.png" \
        -filter_complex "fps=$fps,scale=$width:-1:flags=lanczos[x];[x][1:v]paletteuse" \
        -y "$output" || return 1
}

fit_gif() {
    # Prints a one-line report on stdout; exit 0 = fit, 1 = oversized, 2 = failed
    local input="$1" output="$2"
    local last_size=0
    for tier in "${QUALITY_TIERS[@]}"; do
        # shellcheck disable=SC2086
        read -r fps width colors <<<"$tier"
        if ! build_gif "$input" "$output" "$fps" "$width" "$colors"; then
            echo "ffmpeg failed"
            return 2
        fi
        last_size=$(file_size "$output")
        if [[ $last_size -le $MAX_SIZE_BYTES ]]; then
            printf "%sfps/%spx/%sc, %s" "$fps" "$width" "$colors" "$(human_size "$last_size")"
            return 0
        fi
    done
    printf "%s — over limit" "$(human_size "$last_size")"
    return 1
}

# ---------- PNG conversion ----------
build_png() {
    # build_png <input> <output> [max_width]
    local input="$1" output="$2" width="${3:-}"
    if [[ -n "$width" ]]; then
        if command -v convert >/dev/null 2>&1; then
            convert "$input" -resize "${width}x${width}>" "$output"
        else
            ffmpeg -loglevel error -i "$input" -vf "scale='min($width,iw)':-1" -y "$output"
        fi
    else
        if command -v convert >/dev/null 2>&1; then
            convert "$input" "$output"
        else
            ffmpeg -loglevel error -i "$input" -y "$output"
        fi
    fi
}

fit_png() {
    local input="$1" output="$2"
    local size
    if ! build_png "$input" "$output"; then
        echo "conversion failed"
        return 2
    fi
    size=$(file_size "$output")
    if [[ $size -le $MAX_SIZE_BYTES ]]; then
        human_size "$size"
        return 0
    fi
    for width in "${PNG_QUALITY_TIERS[@]}"; do
        if ! build_png "$input" "$output" "$width"; then
            echo "conversion failed"
            return 2
        fi
        size=$(file_size "$output")
        if [[ $size -le $MAX_SIZE_BYTES ]]; then
            printf "%spx, %s" "$width" "$(human_size "$size")"
            return 0
        fi
    done
    printf "%s — over limit" "$(human_size "$size")"
    return 1
}

# ---------- Per-file handlers ----------
process_video() {
    local input_file="$1"
    local counter; counter=$(get_next_counter)
    local output_file="output/${counter}.gif"
    local archive_file="input/${counter}_$(basename "$input_file")"

    echo "  → $input_file"
    local report rc
    report=$(fit_gif "$input_file" "$output_file"); rc=$?
    case $rc in
        0) echo "    ✓ $output_file  ($report)" ;;
        1) echo "    ⚠ $output_file  ($report)" ;;
        *) echo "    ✗ $input_file  ($report)"; return ;;
    esac
    mv "$input_file" "$archive_file"
}

process_image() {
    local input_file="$1"
    local counter; counter=$(get_next_counter)
    local output_file="output/${counter}.png"
    local archive_file="input/${counter}_$(basename "$input_file")"

    echo "  → $input_file"
    local report rc
    report=$(fit_png "$input_file" "$output_file"); rc=$?
    case $rc in
        0) echo "    ✓ $output_file  ($report)" ;;
        1) echo "    ⚠ $output_file  ($report)" ;;
        *) echo "    ✗ $input_file  ($report)"; return ;;
    esac
    mv "$input_file" "$archive_file"
}

process_passthrough() {
    local input_file="$1"
    local ext="${input_file##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    local counter; counter=$(get_next_counter)
    local output_file="output/${counter}.${ext}"
    local archive_file="input/${counter}_$(basename "$input_file")"

    echo "  → $input_file"
    cp "$input_file" "$output_file"
    local size; size=$(file_size "$output_file")

    if [[ $size -le $MAX_SIZE_BYTES ]]; then
        echo "    ✓ $output_file  ($(human_size "$size"))"
    else
        local before=$size report rc
        rm -f "$output_file"
        if [[ "$ext" == "gif" ]]; then
            report=$(fit_gif "$input_file" "$output_file"); rc=$?
        else
            report=$(fit_png "$input_file" "$output_file"); rc=$?
        fi
        case $rc in
            0) echo "    ↻ $output_file  ($report) [shrunk from $(human_size "$before")]" ;;
            1) echo "    ⚠ $output_file  ($report)" ;;
            *) echo "    ✗ $input_file  ($report)"; return ;;
        esac
    fi
    mv "$input_file" "$archive_file"
}

# ---------- Main ----------
echo "🎯 ${APP_NAME:-$APP} sticker pipeline  (max $(human_size "$MAX_SIZE_BYTES"))"
echo "📁 $(pwd)"
echo

video_count=$(find . -maxdepth 1 \( -name "*.webm" -o -name "*.mp4" \) -type f | wc -l | tr -d ' ')
image_count=$(find . -maxdepth 1 \( -name "*.webp" -o -name "*.jpg" -o -name "*.jpeg" \) -type f | wc -l | tr -d ' ')
pass_count=$(find . -maxdepth 1 \( -name "*.gif" -o -name "*.png" \) -type f | wc -l | tr -d ' ')

if [[ $((video_count + image_count + pass_count)) -eq 0 ]]; then
    echo "Nothing to process."
    exit 0
fi

echo "Found: $video_count video, $image_count image, $pass_count passthrough"
echo

if [[ $video_count -gt 0 ]]; then
    echo "🎬 Videos → GIF"
    find . -maxdepth 1 \( -name "*.webm" -o -name "*.mp4" \) -type f | while read -r file; do
        process_video "$file"
    done
    echo
fi

if [[ $image_count -gt 0 ]]; then
    echo "🖼  Images → PNG"
    find . -maxdepth 1 \( -name "*.webp" -o -name "*.jpg" -o -name "*.jpeg" \) -type f | while read -r file; do
        process_image "$file"
    done
    echo
fi

if [[ $pass_count -gt 0 ]]; then
    echo "📦 Passthrough (GIF/PNG)"
    find . -maxdepth 1 \( -name "*.gif" -o -name "*.png" \) -type f | while read -r file; do
        process_passthrough "$file"
    done
    echo
fi

total_final=$(cat .output_counter)
echo "✅ Done. $((total_final - 1)) total files in output/"
