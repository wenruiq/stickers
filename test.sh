#!/bin/bash

# Test suite for main.sh.
#
# No framework: each test copies main.sh into a throwaway sandbox, drops
# tiny ffmpeg-generated fixtures into its input/, runs the real pipeline,
# and asserts on the output. Hermetic (never touches the repo's own
# input/output/archive) and fast (~1s total).
#
# Run:  ./test.sh

set -uo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

check() {
    # check <description> <expected> <actual>
    if [[ "$2" == "$3" ]]; then
        pass=$((pass + 1))
        printf '  ✓ %s\n' "$1"
    else
        fail=$((fail + 1))
        printf '  ✗ %s\n      expected: %s\n      actual:   %s\n' "$1" "$2" "$3"
    fi
}

check_contains() {
    # check_contains <description> <needle> <haystack>
    if [[ "$3" == *"$2"* ]]; then
        pass=$((pass + 1))
        printf '  ✓ %s\n' "$1"
    else
        fail=$((fail + 1))
        printf '  ✗ %s\n      expected output to contain: %s\n      actual: %s\n' "$1" "$2" "$3"
    fi
}

# ---------- Fixtures ----------
# One frame / a few frames at 32px — big enough to be a real file for
# ffmpeg, small enough that a full encode is instant.
FIX="$TMP/fixtures"
mkdir -p "$FIX"
ffmpeg -nostdin -loglevel error -f lavfi -i color=c=red:s=32x32  -frames:v 1 -y "$FIX/src.png" || exit 1
ffmpeg -nostdin -loglevel error -f lavfi -i color=c=blue:s=32x32 -frames:v 1 -y "$FIX/src.jpg" || exit 1
ffmpeg -nostdin -loglevel error -f lavfi -i testsrc=s=32x32:d=0.3:r=10 -y "$FIX/src.mp4" || exit 1
ffmpeg -nostdin -loglevel error -f lavfi -i testsrc=s=32x32:d=0.3:r=10 -y "$FIX/src.gif" || exit 1

sandbox() {
    # Fresh copy of the script + rules. Prints the sandbox dir.
    local d
    d=$(mktemp -d "$TMP/sbx.XXXXXX")
    cp "$REPO/main.sh" "$d/"
    mkdir -p "$d/.rules" "$d/input"
    cp "$REPO"/.rules/*.sh "$d/.rules/"
    # An unsatisfiable rule with a single tier: exercises the over-limit
    # path without grinding through eight real encodes.
    cat > "$d/.rules/tiny.sh" <<'RULE'
APP_NAME="Tiny"
MAX_SIZE_BYTES=1
QUALITY_TIERS=("5 32 8")
PNG_QUALITY_TIERS=(32)
RULE
    echo "$d"
}

drop() {
    # drop <sandbox> <fixture-ext> <name-in-input>
    cp "$FIX/src.$2" "$1/input/$3"
}

count() { ls -1 "$1" 2>/dev/null | wc -l | tr -d ' '; }

# ---------- Tests ----------

echo "CLI"
d=$(sandbox)
out=$("$d/main.sh" --help 2>&1); rc=$?
check "--help exits 0" 0 "$rc"
check_contains "--help shows usage" "Usage:" "$out"

out=$("$d/main.sh" --list 2>&1); rc=$?
check "--list exits 0" 0 "$rc"
check_contains "--list names seatalk" "seatalk" "$out"

out=$("$d/main.sh" --bogus 2>&1); rc=$?
check "unknown arg exits 1" 1 "$rc"

out=$("$d/main.sh" --app nosuchapp 2>&1); rc=$?
check "missing rule file exits 1" 1 "$rc"
check_contains "missing rule file explains itself" "Rule file not found" "$out"

echo
echo "Empty input"
d=$(sandbox)
out=$("$d/main.sh" 2>&1); rc=$?
check "empty input/ exits 0" 0 "$rc"
check_contains "empty input/ says so" "nothing to process" "$out"

echo
echo "Uppercase extensions (regression: find -name was case-sensitive)"
d=$(sandbox)
drop "$d" png A.PNG
drop "$d" jpg B.JPG
drop "$d" mp4 C.MP4
drop "$d" gif D.GIF
out=$("$d/main.sh" 2>&1)
check "all 4 uppercase sources produce output" 4 "$(count "$d/output")"
check "input/ drained" 0 "$(count "$d/input")"
check "originals archived" 4 "$(count "$d/archive")"
check ".MP4 became a gif" "yes" "$([[ -f "$d/output/3.gif" ]] && echo yes || echo no)"
check ".JPG became a png" "yes" "$([[ -f "$d/output/2.png" ]] && echo yes || echo no)"
check_contains "counted as 1 video" "1 video" "$out"
check_contains "counted as 1 image" "1 image" "$out"
check_contains "counted as 2 passthrough" "2 passthrough" "$out"

echo
echo "Video containers beyond .mp4"
d=$(sandbox)
for ext in mov webm mkv avi m4v; do drop "$d" mp4 "clip.$ext"; done
out=$("$d/main.sh" 2>&1)
check_contains "all 5 containers counted as video" "5 video" "$out"
check "each became a gif" 5 "$(ls -1 "$d"/output/*.gif 2>/dev/null | wc -l | tr -d ' ')"
check "input/ drained" 0 "$(count "$d/input")"

echo
echo "Lowercase extensions"
d=$(sandbox)
drop "$d" png a.png
drop "$d" jpg b.jpg
drop "$d" mp4 c.mp4
drop "$d" gif d.gif
"$d/main.sh" >/dev/null 2>&1
check "all 4 lowercase sources produce output" 4 "$(count "$d/output")"
check "input/ drained" 0 "$(count "$d/input")"

echo
echo "Mixed case within one name"
d=$(sandbox)
drop "$d" jpg "Photo.JpEg"
drop "$d" png "Shot.PnG"
"$d/main.sh" >/dev/null 2>&1
check "odd-case extensions still match" 2 "$(count "$d/output")"

echo
echo "Counter"
d=$(sandbox)
drop "$d" png first.png
"$d/main.sh" >/dev/null 2>&1
drop "$d" png second.png
"$d/main.sh" >/dev/null 2>&1
check "second run does not overwrite the first" 2 "$(count "$d/output")"
check "numbering continues across runs" "yes" "$([[ -f "$d/output/1.png" && -f "$d/output/2.png" ]] && echo yes || echo no)"

echo
echo "Skipped inputs"
d=$(sandbox)
cp "$FIX/src.png" "$d/input/.hidden.png"
mkdir -p "$d/input/nested"
cp "$FIX/src.png" "$d/input/nested/deep.png"
cp "$FIX/src.png" "$d/input/keep.txt"
out=$("$d/main.sh" 2>&1); rc=$?
check "nothing processed" 0 "$rc"
check_contains "no matching sources found" "nothing to process" "$out"
check "dotfile left alone" "yes" "$([[ -f "$d/input/.hidden.png" ]] && echo yes || echo no)"
check "subdirectory not recursed" "yes" "$([[ -f "$d/input/nested/deep.png" ]] && echo yes || echo no)"
check "unknown extension left alone" "yes" "$([[ -f "$d/input/keep.txt" ]] && echo yes || echo no)"

echo
echo "Over the size limit"
d=$(sandbox)
drop "$d" png big.png
drop "$d" mp4 big.mp4
out=$("$d/main.sh" --app tiny 2>&1)
check "no output written" 0 "$(count "$d/output")"
check "sources kept in input/ for a retry" 2 "$(count "$d/input")"
check "nothing archived" 0 "$(count "$d/archive")"
check_contains "reports the overage" "over limit" "$out"

echo
echo "Stray sources at the repo root"
d=$(sandbox)
cp "$FIX/src.png" "$d/stray.PNG"
out=$("$d/main.sh" 2>&1)
check_contains "warns about the misplaced file" "They belong in ./input/" "$out"
check_contains "names it" "stray.PNG" "$out"
check "does not process it" "yes" "$([[ -f "$d/stray.PNG" ]] && echo yes || echo no)"

echo
echo "Filenames with spaces"
d=$(sandbox)
drop "$d" png "my sticker.PNG"
"$d/main.sh" >/dev/null 2>&1
check "space in name handled" 1 "$(count "$d/output")"
check "archived under its original name" "yes" "$([[ -f "$d/archive/1_my sticker.PNG" ]] && echo yes || echo no)"

# ---------- Summary ----------
echo
if [[ $fail -eq 0 ]]; then
    echo "✅ $pass passed"
    exit 0
fi
echo "❌ $fail failed, $pass passed"
exit 1
