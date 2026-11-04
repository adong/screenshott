#!/bin/sh
# Screenshott workflow step: a 1x copy of a 2x capture. Writes it into the step's own
# output folder and hands it back as "image", so the next step (copy) gets it instead
# of the original. A 1x capture goes on unchanged.
set -eu

if [ "$SCREENSHOTT_SCALE" = "1" ]; then
    echo '{"notify": "Already 1x, copied as is"}'
    exit 0
fi
width=$(( SCREENSHOTT_WIDTH / SCREENSHOTT_SCALE ))
height=$(( SCREENSHOTT_HEIGHT / SCREENSHOTT_SCALE ))
# sips reports on stdout; stdout is for the answer, so send that to stderr.
/usr/bin/sips --resampleWidth "$width" -s dpiWidth 72 -s dpiHeight 72 \
    "$SCREENSHOTT_IMAGE" --out "$SCREENSHOTT_OUTPUT_DIR/1x.png" >&2
# A relative path is read from the output folder, so nothing needs escaping.
printf '{"image": "1x.png", "notify": "Copied at %d × %d"}\n' "$width" "$height"
