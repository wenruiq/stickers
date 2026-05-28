#!/bin/bash

# Sticker conversion pipeline with pluggable per-app rules.
#
# Layout:
#   input/     — drop source files here (.mp4 .webm .jpg .jpeg .webp .gif .png)
#   output/    — converted, size-capped stickers (1.gif, 2.png, …)
#   archive/   — originals tidied here after processing
#   .rules/    — per-app size rules (advanced; pick one with --app <name>)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INPUT_DIR="$SCRIPT_DIR/input"
OUTPUT_DIR="$SCRIPT_DIR/output"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
RULES_DIR="$SCRIPT_DIR/.rules"
COUNTER_FILE="$SCRIPT_DIR/.output_counter"

# ---------- Argument parsing ----------
APP="seatalk"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --app)    APP="$2"; shift 2 ;;
        --app=*)  APP="${1#*=}"; shift ;;
        --list)
            echo "Available rule sets:"
            for r in "$RULES_DIR"/*.sh; do
                [[ -f "$r" ]] && echo "  - $(basename "${r%.sh}")"
            done
            exit 0
            ;;
        -h|--help)
            cat <<EOF
Usage: $(basename "$0") [--app <name>] [--list] [--help]

Converts sources in ./input/ into size-capped stickers in ./output/.
Originals are moved to ./archive/ after processing.

Options:
  --app <name>   Rule set to apply (default: seatalk)
  --list         List available rule sets
  -h, --help     Show this help

Advanced: add a new app by creating ./.rules/<name>.sh defining
MAX_SIZE_BYTES, QUALITY_TIERS, and PNG_QUALITY_TIERS.
EOF
            exit 0
            ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

RULE_FILE="$RULES_DIR/${APP}.sh"
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
mkdir -p "$INPUT_DIR" "$OUTPUT_DIR" "$ARCHIVE_DIR"
[[ -f "$COUNTER_FILE" ]] || echo "1" > "$COUNTER_FILE"

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
    current=$(cat "$COUNTER_FILE")
    echo "$current"
    echo $((current + 1)) > "$COUNTER_FILE"
}

list_inputs() {
    # list_inputs <dir> <pattern1> [pattern2 ...]
    local dir="$1"; shift
    local find_args=()
    local first=1
    for pat in "$@"; do
        if [[ $first -eq 1 ]]; then
            find_args+=(-name "$pat")
            first=0
        else
            find_args+=(-o -name "$pat")
        fi
    done
    find "$dir" -maxdepth 1 -type f \( "${find_args[@]}" \) ! -name ".*" 2>/dev/null
}

# ---------- GIF conversion ----------
build_gif() {
    local input="$1" output="$2" fps="$3" width="$4" colors="$5"
    ffmpeg -loglevel error -i "$input" \
        -vf "fps=$fps,scale=$width:-1:flags=lanczos,palettegen=max_colors=$colors" \
        -y "/tmp/palette.png" || return 1
    ffmpeg -loglevel error -i "$input" -i "/tmp/palette.png" \
        -filter_complex "fps=$fps,scale=$width:-1:flags=lanczos[x];[x][1:v]paletteuse" \
        -y "$output" || return 1
}

fit_gif() {
    local input="$1" output="$2"
    local last_size=0
    for tier in "${QUALITY_TIERS[@]}"; do
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
    local output_file="$OUTPUT_DIR/${counter}.gif"
    local archive_file="$ARCHIVE_DIR/${counter}_$(basename "$input_file")"

    echo "  → $(basename "$input_file")"
    local report rc
    report=$(fit_gif "$input_file" "$output_file"); rc=$?
    case $rc in
        0) echo "    ✓ output/${counter}.gif  ($report)" ;;
        1) echo "    ⚠ output/${counter}.gif  ($report)" ;;
        *) echo "    ✗ $(basename "$input_file")  ($report)"; return ;;
    esac
    mv "$input_file" "$archive_file"
}

process_image() {
    local input_file="$1"
    local counter; counter=$(get_next_counter)
    local output_file="$OUTPUT_DIR/${counter}.png"
    local archive_file="$ARCHIVE_DIR/${counter}_$(basename "$input_file")"

    echo "  → $(basename "$input_file")"
    local report rc
    report=$(fit_png "$input_file" "$output_file"); rc=$?
    case $rc in
        0) echo "    ✓ output/${counter}.png  ($report)" ;;
        1) echo "    ⚠ output/${counter}.png  ($report)" ;;
        *) echo "    ✗ $(basename "$input_file")  ($report)"; return ;;
    esac
    mv "$input_file" "$archive_file"
}

process_passthrough() {
    local input_file="$1"
    local ext="${input_file##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    local counter; counter=$(get_next_counter)
    local output_file="$OUTPUT_DIR/${counter}.${ext}"
    local archive_file="$ARCHIVE_DIR/${counter}_$(basename "$input_file")"

    echo "  → $(basename "$input_file")"
    cp "$input_file" "$output_file"
    local size; size=$(file_size "$output_file")

    if [[ $size -le $MAX_SIZE_BYTES ]]; then
        echo "    ✓ output/${counter}.${ext}  ($(human_size "$size"))"
    else
        local before=$size report rc
        rm -f "$output_file"
        if [[ "$ext" == "gif" ]]; then
            report=$(fit_gif "$input_file" "$output_file"); rc=$?
        else
            report=$(fit_png "$input_file" "$output_file"); rc=$?
        fi
        case $rc in
            0) echo "    ↻ output/${counter}.${ext}  ($report) [shrunk from $(human_size "$before")]" ;;
            1) echo "    ⚠ output/${counter}.${ext}  ($report)" ;;
            *) echo "    ✗ $(basename "$input_file")  ($report)"; return ;;
        esac
    fi
    mv "$input_file" "$archive_file"
}

# ---------- Misplacement check ----------
# If the user dropped sources at the repo root instead of input/, point them home.
stray=$(list_inputs "$SCRIPT_DIR" "*.mp4" "*.webm" "*.webp" "*.jpg" "*.jpeg" "*.gif" "*.png" | head -n 5)
if [[ -n "$stray" ]]; then
    echo "⚠ Found source files at the repo root. They belong in ./input/"
    while IFS= read -r line; do
        echo "    ${line#$SCRIPT_DIR/}"
    done <<<"$stray"
    echo "    (move them in there and re-run)"
    echo
fi

# ---------- Main ----------
echo "🎯 ${APP_NAME:-$APP} sticker pipeline  (max $(human_size "$MAX_SIZE_BYTES"))"
echo

video_files=$(list_inputs "$INPUT_DIR" "*.mp4" "*.webm")
image_files=$(list_inputs "$INPUT_DIR" "*.webp" "*.jpg" "*.jpeg")
pass_files=$(list_inputs "$INPUT_DIR" "*.gif" "*.png")

video_count=$([[ -z "$video_files" ]] && echo 0 || echo "$video_files" | wc -l | tr -d ' ')
image_count=$([[ -z "$image_files" ]] && echo 0 || echo "$image_files" | wc -l | tr -d ' ')
pass_count=$([[ -z "$pass_files"  ]] && echo 0 || echo "$pass_files"  | wc -l | tr -d ' ')

if [[ $((video_count + image_count + pass_count)) -eq 0 ]]; then
    cat <<EOF
input/ is empty — nothing to process.

  Drop source files into ./input/ and re-run:
    .mp4  .webm           → converted to GIF
    .jpg  .jpeg  .webp    → converted to PNG
    .gif  .png            → passed through (re-encoded only if over the size limit)
EOF
    exit 0
fi

echo "Found in input/: $video_count video, $image_count image, $pass_count passthrough"
echo

if [[ $video_count -gt 0 ]]; then
    echo "🎬 Videos → GIF"
    echo "$video_files" | while read -r file; do
        [[ -n "$file" ]] && process_video "$file"
    done
    echo
fi

if [[ $image_count -gt 0 ]]; then
    echo "🖼  Images → PNG"
    echo "$image_files" | while read -r file; do
        [[ -n "$file" ]] && process_image "$file"
    done
    echo
fi

if [[ $pass_count -gt 0 ]]; then
    echo "📦 Passthrough (GIF/PNG)"
    echo "$pass_files" | while read -r file; do
        [[ -n "$file" ]] && process_passthrough "$file"
    done
    echo
fi

total_final=$(cat "$COUNTER_FILE")
echo "✅ Done. $((total_final - 1)) total files in output/, originals archived in archive/"
