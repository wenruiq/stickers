#!/bin/bash

# Sticker conversion and organization script
# Converts webm to gif, other formats to png
# Organizes files with numerical naming to avoid conflicts

set -e

# Create directories
mkdir -p output
mkdir -p input

# Initialize counter file if it doesn't exist
if [[ ! -f .output_counter ]]; then
    echo "1" > .output_counter
fi

# Function to get next counter value
get_next_counter() {
    local counter_file="$1"
    local current=$(cat "$counter_file")
    echo "$current"
    echo $((current + 1)) > "$counter_file"
}

# Function to convert webm to gif
convert_to_gif() {
    local input_file="$1"
    local counter=$(get_next_counter .output_counter)
    local output_file="output/${counter}.gif"
    local archive_file="input/${counter}_$(basename "$input_file")"
    
    echo "Converting $input_file to GIF..."
    ffmpeg -i "$input_file" -vf "fps=15,scale=320:-1:flags=lanczos,palettegen" -y "/tmp/palette.png"
    ffmpeg -i "$input_file" -i "/tmp/palette.png" -filter_complex "fps=15,scale=320:-1:flags=lanczos[x];[x][1:v]paletteuse" -y "$output_file"
    
    # Move original to archive
    mv "$input_file" "$archive_file"
    echo "✓ Created: $output_file"
    echo "✓ Archived: $archive_file"
}

# Function to convert to png
convert_to_png() {
    local input_file="$1"
    local counter=$(get_next_counter .output_counter)
    local output_file="output/${counter}.png"
    local archive_file="input/${counter}_$(basename "$input_file")"
    
    echo "Converting $input_file to PNG..."
    
    # Use different conversion based on input format
    local ext="${input_file##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    case "$ext" in
        webp)
            # Convert webp to png using ImageMagick or ffmpeg
            if command -v convert >/dev/null 2>&1; then
                convert "$input_file" "$output_file"
            else
                ffmpeg -i "$input_file" -y "$output_file"
            fi
            ;;
        jpg|jpeg)
            # Convert jpg/jpeg to png
            if command -v convert >/dev/null 2>&1; then
                convert "$input_file" "$output_file"
            else
                ffmpeg -i "$input_file" -y "$output_file"
            fi
            ;;
        *)
            # For other formats
            if command -v convert >/dev/null 2>&1; then
                convert "$input_file" "$output_file"
            else
                ffmpeg -i "$input_file" -y "$output_file"
            fi
            ;;
    esac
    
    # Move original to archive
    mv "$input_file" "$archive_file"
    echo "✓ Created: $output_file"
    echo "✓ Archived: $archive_file"
}

# Function to move already-accepted formats
move_accepted_format() {
    local input_file="$1"
    local ext="${input_file##*.}"
    local counter
    local output_file
    local archive_file
    
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    case "$ext" in
        gif)
            counter=$(get_next_counter .output_counter)
            output_file="output/${counter}.gif"
            archive_file="input/${counter}_$(basename "$input_file")"
            echo "Moving $input_file (already GIF format)..."
            ;;
        png)
            counter=$(get_next_counter .output_counter)
            output_file="output/${counter}.png"
            archive_file="input/${counter}_$(basename "$input_file")"
            echo "Moving $input_file (already PNG format)..."
            ;;
    esac
    
    # Copy to output and move original to archive
    cp "$input_file" "$output_file"
    mv "$input_file" "$archive_file"
    echo "✓ Moved: $output_file"
    echo "✓ Archived: $archive_file"
}

# Main processing
echo "🎯 Starting sticker conversion process..."
echo "📁 Current directory: $(pwd)"
echo

# Count files to process
webm_count=$(find . -maxdepth 1 -name "*.webm" -type f | wc -l | tr -d ' ')
convert_count=$(find . -maxdepth 1 \( -name "*.webp" -o -name "*.jpg" -o -name "*.jpeg" \) -type f | wc -l | tr -d ' ')
move_count=$(find . -maxdepth 1 \( -name "*.gif" -o -name "*.png" \) -type f | wc -l | tr -d ' ')

echo "📊 Found $webm_count WebM files (will convert to GIF)"
echo "📊 Found $convert_count image files (will convert to PNG)"
echo "📊 Found $move_count already-accepted files (will move to output)"
echo

if [[ $webm_count -eq 0 && $convert_count -eq 0 && $move_count -eq 0 ]]; then
    echo "ℹ️  No files to process."
    exit 0
fi

# Process WebM files (convert to GIF)
echo "🎬 Processing WebM files..."
find . -maxdepth 1 -name "*.webm" -type f | while read -r file; do
    convert_to_gif "$file"
done

# Process files that need conversion to PNG
echo
echo "🖼️  Converting image files to PNG..."
find . -maxdepth 1 \( -name "*.webp" -o -name "*.jpg" -o -name "*.jpeg" \) -type f | while read -r file; do
    convert_to_png "$file"
done

# Process already-accepted formats (just move and rename)
echo
echo "📁 Moving already-accepted formats..."
find . -maxdepth 1 \( -name "*.gif" -o -name "*.png" \) -type f | while read -r file; do
    move_accepted_format "$file"
done

echo
echo "✅ Conversion complete!"
echo "📁 Converted files are in: output/"
echo "📁 Original files archived in: input/"

# Show summary
total_final=$(cat .output_counter)
echo
echo "📈 Summary:"
echo "   - Total files processed: $((total_final - 1))"