# Ballroom Rounds Maker

An OCaml CLI tool that assembles ballroom dance competition "rounds" -- single
MP3 files composed of multiple songs (one per dance style) separated by
configurable silence breaks. Rounds are defined in `.rounds` files using an
INI-style markup language with configurable song duration, break duration, and
fade timing. The tool orchestrates **ffmpeg** to trim, generate silence, and
concatenate everything into one output file.

## Prerequisites

- **OCaml** (with opam)
- **Dune 3**
- **opam packages:** `core`, `unix`, `menhir`
- **ffmpeg** -- either on your `PATH` or placed as a binary at `./ffmpeg` in the
  project root (the code invokes `./ffmpeg` by default)

Install OCaml dependencies:

```bash
opam install core menhir
```

## The `.rounds` Format

Rounds are defined in `.rounds` files with an INI-style syntax. A `[defaults]`
section sets global timing, and `[round name]` sections list songs and breaks:

```ini
# Comments start with # or ;
[defaults]
song_duration = 90
break_duration = 10
fade_in = 5
fade_out = 5

[round standard_champ_1heat]
Standard/Waltz/Don't Be So Shy (Slow Waltz 29).mp3
break
Standard/Tango/The Punch and Judy Tango.mp3 | start=15 | duration=80
break 15
Standard/VWaltz/Love Story - Indila.mp3 | fade_in=3 | fade_out=8
break
Standard/Fox/Better Together.mp3
break
Standard/Quickstep/Larger Than Life.mp3 | end=105
```

- **Song entries** are relative paths under `hellrounds_source/`. Per-song
  overrides use `| key=value` syntax: `start`, `end`, `duration`, `fade_in`,
  `fade_out`.
- **`break`** uses the default break duration. **`break N`** overrides it with
  `N` seconds.
- **`[defaults]`** is optional -- if omitted, defaults are: `song_duration=90`,
  `break_duration=10`, `fade_in=5`, `fade_out=5`.

## How It Works

The pipeline runs in three stages:

1. **Create artifacts** -- Each entry is turned into an `artifact`. Songs are
   copied from `hellrounds_source/` into `hellrounds_source_artifacts/` with
   normalized filenames. Break entries produce (or reuse cached) silent MP3
   files.
2. **Trim** -- Each `Song` artifact is trimmed with configurable start time,
   duration, fade-in, and fade-out (resolved against defaults) via ffmpeg.
   `Break` artifacts pass through unchanged.
3. **Concatenate** -- All artifact paths are written to a concat demuxer list
   file and ffmpeg produces the final MP3 (192 kbps).

## Usage

### Build

```bash
dune build
```

### Run

```bash
dune exec bin/main.exe -- <rounds_file>
```

For example:

```bash
dune exec bin/main.exe -- sample.rounds
```

Run from the project root so that the relative paths `hellrounds_source/`,
`hellrounds_source_artifacts/`, and `./ffmpeg` resolve correctly. Output MP3
files are written to the `rounds_output/` directory.
