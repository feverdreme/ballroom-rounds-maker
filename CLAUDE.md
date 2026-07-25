# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

OCaml CLI that assembles ballroom dance competition "rounds" — single MP3s composed of multiple songs (one per dance style) separated by configurable silence breaks. Rounds are described in `.rounds` files (INI-style); the tool orchestrates `ffmpeg` to trim, generate silence, and concatenate.

## Commands

```bash
# Build
dune build

# Run (must be run from project root so relative paths resolve)
dune exec bin/main.exe -- <rounds_file>
dune exec bin/main.exe -- sample.rounds

# CLI flags (all optional, defaults shown)
#   --source-dir     hellrounds_source
#   --artifacts-dir  hellrounds_source_artifacts
#   --output-dir     rounds_output
#   --ffmpeg-path    ./ffmpeg
```

Dependencies: `core`, `unix`, `menhir` via opam. `ffmpeg` must be at `./ffmpeg` or on PATH (override with `--ffmpeg-path`). No test suite exists.

## Architecture

Two dune units: `lib/` (library `ballroom_rounds_maker_lib`) and `bin/main.ml` (thin CLI wrapper parsing args and iterating rounds).

**Pipeline** — `bin/main.ml` `process_round` runs three stages per round, mirroring the library modules:

1. `create_artifact` ([lib/generate_artifacts.ml](lib/generate_artifacts.ml)) — turns each parsed entry into an `artifact`. Songs are copied from source-dir into artifacts-dir with normalized filenames; breaks become (or reuse cached) `break_<N>.mp3` silent files.
2. `trim_artifact` — each `Song` is trimmed via ffmpeg using `start`/`duration`/`fade_in`/`fade_out` resolved against `defaults`. Breaks pass through.
3. `concat_artifacts` — writes a concat demuxer list and produces the final 192 kbps MP3 under the output directory.

The `artifact` type is a sum of `Break {path; duration}` and `Song {path; config}`. Each pipeline stage returns new artifacts with updated paths (the docstring calls it "the artifact monad"), so stages can be composed without mutating.

**Parsing** — `.rounds` files use a hand-written context-sensitive tokenizer ([lib/parse_rounds.ml](lib/parse_rounds.ml)) that feeds a menhir grammar ([lib/parser.mly](lib/parser.mly)). The tokenizer is context-sensitive because song paths contain spaces/brackets/parens and must only be recognized inside `[round ...]` sections — not in `[defaults]` or at top-level. Modes: `Toplevel | InDefaults | InRound`. BNF lives in [bnf.md](bnf.md).

Grammar highlights: `[defaults]` is optional (falls back to `default_defaults` in `generate_artifacts.ml`: 90/10/5/5). Entries in a round are either `break [N]` or `<path> (| key=value)*` where keys are `start`/`end`/`duration`/`fade_in`/`fade_out`. `resolve_config` enforces that if both `duration` and `end` are given, `start + duration = end`.

**Support modules**: [lib/file_utils.ml](lib/file_utils.ml) (mkdir_p, copy_file, normalize_filename), [lib/audio_processing.ml](lib/audio_processing.ml) (ffmpeg invocations: `generate_silence`, `ffmpeg_trim`, `ffmpeg_concat`, `seconds_to_ffmpeg_time`).

## Conventions

- Song paths in `.rounds` files are relative to `--source-dir` (default `hellrounds_source/`).
- Output filenames are `<round_name>.mp3` under `--output-dir`.
- When adding a new `| key=value` song option, update the tokenizer's option parsing, the menhir grammar, `song_config`, and `resolve_config` together.
