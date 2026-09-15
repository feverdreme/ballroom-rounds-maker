# Project instructions

## Overview

This is an OCaml/Dune CLI and TUI for converting ballroom-dance competition
round descriptions into concatenated MP3 files. The library models rounds and
invokes `ffmpeg` to trim songs, generate silence for breaks, and concatenate
the resulting artifacts.

## Repository layout

- `lib/` contains the `rounds_lib` library (`Round`, `Base_path`, and `Ffmpeg`).
- `lib_tui/` contains the Bonsai terminal UI in `rounds_tui_lib`.
- `lib_web/` contains the shared sexp protocol, Bonsai web client, and local
  Async/Cohttp server.
- `bin/main.ml` is the MP3 conversion CLI.
- `bin/tui.ml` is the terminal UI entry point.
- `README.md` documents the current S-expression input format and CLI flags.

## Development commands

```bash
# Build all libraries and executables
dune build

# Run the converter
dune exec bin/main.exe -- \
  -round-file <round.sexp> \
  -output <output.mp3> \
  -artifact-path <artifacts_dir> \
  [-source-path <source_dir>] \
  [-ffmpeg-path <ffmpeg_path>]

# Run the TUI
dune exec bin/tui.exe

# Run the local web editor
dune exec bin/web.exe
```

Dependencies are managed with opam. The Dune files use `core`, `core_unix`,
`unix`, `ppx_jane`, `async`, `bonsai`, `bonsai_term`, `bonsai_web`,
`js_of_ocaml`, and `cohttp-async`. `ffmpeg` must be on
`PATH` unless `-ffmpeg-path` is supplied.

Run `dune build` after code changes. The web protocol has serialization
round-trip tests that run through `dune runtest`.

## Implementation notes

- `Round.t` is serialized with Jane Street S-expressions; preserve its sexp
  shape when changing the model.
- `Round.Song.create` validates that fade-in plus fade-out does not exceed the
  song duration.
- Keep the web protocol native to the OCaml codebase: send S-expressions over
  HTTP and reuse derived sexp converters rather than adding parallel JSON DTOs.
- Keep web-protocol tests focused on serialization round trips; do not broaden
  them into API, UI, filesystem, or smoke tests unless explicitly requested.
- `bin/main.ml` stable-deduplicates events by `Round.Event.to_string`, creates
  or reuses artifact files, and then invokes the concat step.
- Paths are resolved relative to the supplied source/artifact directories.
- `Ffmpeg` shells out to the configured executable. Quote or validate any new
  paths and arguments consistently with the existing code.
- Keep the `.mli` files synchronized with implementation changes.

## Change discipline

- Do not modify generated `_build/` contents or large audio assets.
- Preserve unrelated working-tree changes.
- Prefer small, focused patches and update `README.md` when CLI behavior or
  input format changes.
