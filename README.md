# Ballroom Rounds Maker

An OCaml CLI tool that assembles ballroom dance competition "rounds" -- single
MP3 files composed of multiple songs (one per dance style) separated by
configurable silence breaks. A round is described as a `Round.t` value
serialized to a sexp file. The tool orchestrates **ffmpeg** to trim each song,
generate silence for breaks, and concatenate everything into one output file.

## Prerequisites

- **OCaml** (with opam)
- **Dune 3**
- **opam packages:** `core`, `core_unix`, `unix`, `ppx_jane`
- **ffmpeg** -- must be on your `PATH`, or pass `-ffmpeg-path` to point at a
  specific binary

Install OCaml dependencies:

```bash
opam install core core_unix ppx_jane
```

## The round sexp format

A round is a `Round.t` sexp file with a `name` and a list of `events`. Each
event is either a `Song` (with a `filepath` relative to `-source-path`,
`duration`, `fade_in`, and `fade_out` in seconds, plus optional `name` and
`dance`) or a `Break` (with a `duration` in seconds):

```lisp
((name standard_champ_1heat)
 (events
  ((Song
    (song
     ((filepath "Standard/Waltz/Don't Be So Shy (Slow Waltz 29).mp3")
      (duration 90) (fade_in 5) (fade_out 5)))
    (name ()) (dance ()))
   (Break ((duration 10)))
   (Song
    (song
     ((filepath "Standard/Tango/The Punch and Judy Tango.mp3")
      (duration 80) (fade_in 5) (fade_out 5)))
    (name ()) (dance ()))
   (Break ((duration 15))))))
```

Sample round files live in [rounds/](rounds/). `Round.t` values are typically
produced programmatically (via `Round.save_to_file`) rather than hand-written.

## How It Works

`bin/main.ml` reads a `Round.t` sexp file and runs the pipeline in
`convert_round`:

1. **Deduplicate events** -- events are stable-deduped by their string
   representation (song path + fade/duration, or break duration) so repeated
   entries reuse the same artifact.
2. **Create + trim artifacts** -- each unique `Song` is trimmed from
   `-source-path` with its configured duration, fade-in, and fade-out via
   ffmpeg; each unique `Break` becomes a generated silent MP3 (skipped if it
   already exists). Artifact filenames are derived from the event's string
   representation under `-artifact-path`.
3. **Concatenate** -- all artifact paths are written to an ffmpeg concat
   demuxer list and ffmpeg produces the final MP3 (192 kbps) at `-output`.

## Usage

### Build

```bash
dune build
```

### Run

```bash
dune exec bin/main.exe -- \
  -round-file <round.sexp> \
  -output <output.mp3> \
  -artifact-path <artifacts_dir> \
  [-source-path <source_dir>] \
  [-ffmpeg-path <path_to_ffmpeg>]
```

For example:

```bash
dune exec bin/main.exe -- \
  -round-file rounds/standard_champ_1heat.sexp \
  -output rounds_output/standard_champ_1heat.mp3 \
  -artifact-path hellrounds_source_artifacts \
  -source-path hellrounds_source
```

Flags:

- `-round-file` (required) -- sexp file describing the round (`Round.t`).
- `-output` (required) -- output MP3 path.
- `-artifact-path` (required) -- directory for intermediate artifacts
  (trimmed songs, breaks, concat list). Created if it doesn't exist.
- `-source-path` (optional, default `.`) -- base directory that song
  `filepath`s are resolved against.
- `-ffmpeg-path` (optional, default `ffmpeg`) -- path to the ffmpeg binary.
