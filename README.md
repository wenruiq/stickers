# Sticker Converter

Batch convert and organize sticker files with consistent naming.

## Requirements

```bash
brew install ffmpeg imagemagick
```

## Usage

1. Place files you want to convert (`.webm`, `.webp`, `.jpg`, `.jpeg`, `.gif`, `.png`) in the root directory
2. Run in your terminal: `./main.sh`

## Supported Formats

**Input:**

-   `.webm` → converts to `.gif`
-   `.webp`, `.jpg`, `.jpeg` → converts to `.png`
-   `.gif`, `.png` → organizes to output (no conversion needed)

**Output:**

-   `output/` - converted files with sequential naming (1.gif, 2.png, 3.gif...)
-   `input/` - original files with prefixed names

## File Processing

-   Sequential numbering prevents naming conflicts
-   Original files preserved in archive
-   Supports mixed file types in single run
-   WebM conversion optimized for stickers (15fps, 320px width)
