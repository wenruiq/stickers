# Sticker Converter

Turn any video or image into a chat-ready **SeaTalk sticker** (≤2MB). Drop files in, run one command, get sized stickers out.

## Quick start

```bash
brew install ffmpeg imagemagick   # one-time

# 1. Drop your files into  ./input
# 2. Run:
./main.sh
# 3. Grab your stickers from  ./output
```

Originals are moved to `./archive`. Output is numbered (`1.gif`, `2.png`, …) and keeps counting up across runs — nothing gets overwritten.

> **ffmpeg** is required. **ImageMagick** is optional — only used for images, where it gives sharper resizing; without it, ffmpeg handles images too. The script checks for both on startup.

## What goes in → what comes out

| You drop                                        | You get | What happens                                |
| ---------------------------------------------- | ------- | ------------------------------------------- |
| `.mp4`, `.mov`, `.webm`, `.mkv`, `.avi`, `.m4v` | `.gif`  | Re-encoded down until it fits under 2MB.    |
| `.jpg`, `.jpeg`, `.webp`                        | `.png`  | Downscaled in steps if too large.           |
| `.gif`, `.png`                                  | same    | Kept as-is, or re-encoded down if over 2MB. |

`output/` only ever contains files that fit the limit. Anything that can't be sized down stays in `input/` so you can fix it and retry.

## Grab a sticker from 7TV (Claude Code)

This repo bundles a Claude Code skill. Open the repo in Claude Code and just ask:

> *"get me the peepoHappy gif as a SeaTalk sticker"*

It finds the [7TV](https://7tv.app) emote, downloads it to `input/`, and runs the pipeline for you. No setup — Claude Code auto-discovers the skill.

## Commands

```bash
./main.sh             # process input/
./main.sh --help      # usage
./main.sh --list      # list available app rule sets
./main.sh --app NAME  # use a different app's size rules
```

```bash
./test.sh             # run the test suite (~4s, needs ffmpeg)
```

To reset everything and restart numbering from 1:

```bash
rm -rf output/* archive/* .output_counter
```

## Adding another chat app

Each app has its own size cap, defined in `.rules/`. Copy SeaTalk's and edit:

```bash
cp .rules/seatalk.sh .rules/telegram.sh   # then edit, and run:
./main.sh --app telegram
```

Three constants control the output:

- `MAX_SIZE_BYTES` — per-file size cap
- `QUALITY_TIERS` — GIF settings tried in order (`"<fps> <width> <colors>"`), best first
- `PNG_QUALITY_TIERS` — max widths tried for oversized PNGs

The script walks the tiers top-down and keeps the first encode that fits — so you always get the best quality that hits the cap.
