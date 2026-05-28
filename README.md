# Sticker Converter

Drop your videos and images in, get chat-ready stickers out — automatically sized to your chat app's limit. Configured by default for **SeaTalk** (2MB per sticker).

## TL;DR

```bash
brew install ffmpeg imagemagick   # one-time
chmod +x main.sh                  # one-time
# drop your source files into ./input
./main.sh                         # → output goes to ./output, originals goes to ./archive
```

---

## Setup (one time)

```bash
brew install ffmpeg imagemagick
```

## Use it

```
1. Drop files into ./input/
2. Run ./main.sh
3. Find stickers in ./output/
```

That's it. Originals are tidied into `./archive/` so you can always find them again.

### What it accepts


| You drop                 | You get | Notes                                                     |
| ------------------------ | ------- | --------------------------------------------------------- |
| `.mp4`, `.webm`          | `.gif`  | Re-encoded down until it fits under the size limit.       |
| `.jpg`, `.jpeg`, `.webp` | `.png`  | Downscaled in steps if too large.                         |
| `.gif`, `.png`           | same    | Copied as-is, or re-encoded if it exceeds the size limit. |


Output is numbered sequentially (`1.gif`, `2.png`, `3.gif`, …) and keeps counting upward across runs, so you can keep adding stickers indefinitely without overwriting anything.

## What a run looks like

```
🎯 SeaTalk sticker pipeline  (max 2.00MB)

Found in input/: 2 video, 1 image, 0 passthrough

🎬 Videos → GIF
  → clip1.mp4
    ✓ output/17.gif  (15fps/320px/256c, 1.42MB)
  → clip2.webm
    ↻ output/18.gif  (12fps/280px/128c, 1.78MB)

🖼  Images → PNG
  → photo.jpg
    ✓ output/19.png  (87KB)

✅ Done. 19 total files in output/, originals archived in archive/
```

Status markers:

- `✓` — fit on the first attempt, full quality
- `↻` — fit, but the script had to step quality down
- `⚠` — exhausted all quality steps and the file is still over the limit (kept anyway)
- `✗` — conversion failed; the original stays in `input/`

## CLI

```
./main.sh             # process input/
./main.sh --help      # show usage
./main.sh --list      # list available app rule sets
./main.sh --app NAME  # use a different rule set
```

## Resetting

To wipe processed files and restart numbering from 1:

```bash
rm -rf output/* archive/* .output_counter
```

`input/` should already be empty after a clean run.

## Layout

```
[Z] Stickers/
├── main.sh
├── README.md
├── input/       ← you drop sources here
├── output/      ← processed stickers
├── archive/     ← originals tidied here after processing
└── .rules/      ← per-app size rules (hidden; only touch if adding apps)
```

`input/`, `output/`, and `archive/` ship empty (with a `.gitkeep` placeholder); your personal files in them are gitignored.

---

## Advanced: adding a new app

Each chat app has its own size cap. To add one, drop a config into `.rules/`:

```bash
cp .rules/seatalk.sh .rules/telegram.sh
```

Edit the three constants in the new file:

- `MAX_SIZE_BYTES` — the per-file size cap
- `QUALITY_TIERS` — GIF tiers tried in order, each `"<fps> <width> <colors>"`
- `PNG_QUALITY_TIERS` — max widths tried for oversized PNGs

Then:

```bash
./main.sh --app telegram
```

### How the size cap is enforced

For each source the script walks the rule's quality tiers in order and keeps the first encode that fits under `MAX_SIZE_BYTES`. So you always get the best-quality version that hits the cap, not a one-size-fits-all downsample.

GIF tier example (SeaTalk):

```
fps  width  colors
 15  320    256     ← try first (best quality)
 15  320    192
 12  320    128
 12  280    128
 10  240     96
  8  200     64     ← last resort
```

