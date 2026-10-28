#!/usr/bin/env bash
set -euo pipefail

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

# Stub audio processing: this regression checks the converter's concat manifest.
"$1" -round-file "$2" -output "$test_dir/output.mp3" \
  -artifact-path "$test_dir/artifacts" -ffmpeg-path /usr/bin/true

song="$test_dir/artifacts/sample.mp3_fadein_0_duration_2_fadeout_0.mp3"
pause="$test_dir/artifacts/break_1.mp3"
printf "file '%s'\n" "$song" "$pause" "$song" "$pause" > "$test_dir/expected.txt"
diff -u "$test_dir/expected.txt" "$test_dir/artifacts/concat_list.txt"
