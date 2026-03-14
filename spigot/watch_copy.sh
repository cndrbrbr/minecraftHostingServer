#!/bin/bash
#######################################################
# copy file to volume whenever it changes
# usage: ./watch_copy.sh <source_file> <dest_file_or_dir>
# (c) 2025 cndrbrbr
#######################################################
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <source_file> <destination_path_or_file>"
    exit 1
fi

SOURCE_FILE="$1"
DEST_PATH="$2"

if [ ! -f "$SOURCE_FILE" ]; then
    echo "watch_copy: source not found: $SOURCE_FILE"
    exit 2
fi

if [ -d "$DEST_PATH" ]; then
    DEST_FILE="$DEST_PATH/$(basename "$SOURCE_FILE")"
else
    DEST_FILE="$DEST_PATH"
    mkdir -p "$(dirname "$DEST_FILE")"
fi

echo "watch_copy: watching $SOURCE_FILE → $DEST_FILE"

inotifywait -m -e modify -e close_write -e attrib "$SOURCE_FILE" |
while read -r path event file; do
    echo "watch_copy: change detected ($event) → copying"
    cp -f "$SOURCE_FILE" "$DEST_FILE"
done
