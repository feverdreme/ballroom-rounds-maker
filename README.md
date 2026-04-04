# Ballroom Rounds Maker

An OCaml CLI tool that assembles ballroom dance competition "rounds" -- single
MP3 files composed of multiple songs (one per dance style) separated by
configurable silence breaks. Each song is trimmed to 90 seconds with a 5-second
fade-in and 5-second fade-out. The tool orchestrates **ffmpeg** to trim,
generate silence, and concatenate everything into one output file.

## Prerequisites

- **OCaml** (with opam)
- **Dune 3**
- **opam packages:** `core`, `unix`
- **ffmpeg** -- either on your `PATH` or placed as a binary at `./ffmpeg` in the
  project root (the code invokes `./ffmpeg` by default)

Install OCaml dependencies:

```bash
opam install core
```

## How It Works

A round is defined as a list of strings in `bin/main.ml`:

```ocaml
let standard_champ_1heat =
  [ "Standard/Waltz/Don't Be So Shy (Slow Watlz 29)_spotdown.org.mp3"
  ; "<BREAK> 10"
  ; "Standard/Tango/The Punch and Judy Tango (Tango)_spotdown.org.mp3"
  ; "<BREAK> 10"
  ; "Standard/VWaltz/Love Story - Indila.mp3"
  ; "<BREAK> 10"
  ; "Standard/Fox/Better Together_spotdown.org.mp3"
  ; "<BREAK> 10"
  ; "Standard/Quickstep/Larger Than Life (feat. Benji Jackson)_spotdown.org.mp3"
  ]
```

The pipeline then runs in three stages:

1. **Create artifacts** -- Each entry is turned into an `artifact`. Songs are
   copied from `hellrounds_source/` into `hellrounds_source_artifacts/` with
   normalized filenames. Break entries produce (or reuse cached) silent MP3
   files.
2. **Trim** -- Each `Song` artifact is trimmed to 90 seconds with a 5-second
   fade-in and 5-second fade-out via ffmpeg. `Break` artifacts pass through
   unchanged.
3. **Concatenate** -- All artifact paths are written to a concat demuxer list
   file and ffmpeg produces the final MP3 (192 kbps).

## Usage

### Build

```bash
dune build
```

### Run

```bash
dune exec bin/main.exe
```

Run from the project root so that the relative paths `hellrounds_source/`,
`hellrounds_source_artifacts/`, and `./ffmpeg` resolve correctly.

### Customizing Rounds

Edit the round definitions in `bin/main.ml`. Each round is a string list where:

- **Song entries** are relative paths under `hellrounds_source/` (e.g.
  `"Latin/Cha/Undress Rehearsal.mp3"`)
- **Break entries** use the format `"<BREAK> N"` where `N` is seconds of silence

Then call `create_hell_rounds` with your list and desired output filename:

```ocaml
let () =
  create_hell_rounds my_custom_round "my_custom_round.mp3"
```

The output MP3 is written to the project root.

The `source_directory` and `artifacts_directory` variables inside
`create_hell_rounds` can be changed to any paths you like -- they default to
`hellrounds_source` and `hellrounds_source_artifacts` but there is nothing
special about those names.
