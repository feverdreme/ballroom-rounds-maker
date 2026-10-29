# Project instructions

These instructions are shared conceptually with `AGENTS.md` for Codex. Keep
both files aligned when changing repository conventions.

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
- `lib_mcp/` contains the stdio MCP server in `rounds_mcp_server`.
- `bin/main.ml` is the MP3 conversion CLI.
- `bin/tui.ml` is the terminal UI entry point.
- `bin/mcp.ml` is the MCP server entry point.
- `README.md` documents the current S-expression input format and CLI flags.
- `.agents/skills/rounds/` is the agent skill for authoring, downloading, and
  producing rounds; it prefers the MCP tools when they are configured.

## Development commands

```bash
dune build
dune exec bin/main.exe -- -round-file <round.sexp> -output <output.mp3> -artifact-path <artifacts_dir> [-source-path <source_dir>] [-ffmpeg-path <ffmpeg_path>]
dune exec bin/tui.exe
dune exec bin/web.exe
dune exec bin/mcp.exe -- -rounds-path <dir> -source-path <dir> -artifact-path <dir> -output-path <dir>
```

Dependencies are managed with opam. The Dune files use `core`, `core_unix`,
`unix`, `ppx_jane`, `async`, `bonsai`, `bonsai_term`, `bonsai_web`,
`js_of_ocaml`, `cohttp-async`, and `yojson`. `ffmpeg` must be on
`PATH` unless `-ffmpeg-path` is supplied. Run `dune build` after code changes;
the web protocol's serialization round-trip tests run through `dune runtest`.

## Implementation notes

- `Round.t` is serialized with Jane Street S-expressions; preserve its sexp
  shape when changing the model.
- `Round.Song.create` validates that fade-in plus fade-out does not exceed the
  song duration.
- Keep the web protocol native to the OCaml codebase: send S-expressions over
  HTTP and reuse derived sexp converters rather than adding parallel JSON DTOs.
- Keep web-protocol tests focused on serialization round trips; do not broaden
  them into API, UI, filesystem, or smoke tests unless explicitly requested.
- `Converter.convert` (used by `bin/main.ml`) stable-deduplicates events by
  `Round.Event.to_string`, creates or reuses artifact files, and then invokes
  the concat step.
- Paths are resolved relative to the supplied source/artifact directories.
- `Ffmpeg` shells out to the configured executable. Quote or validate any new
  paths and arguments consistently with the existing code.
- The MCP server's `produce_round` tool reuses `Converter.convert`.
- The MCP server owns stdout for JSON-RPC and redirects fd 1 to stderr at
  startup; keep any new subprocess or progress output off the protocol stream.
  Tool payloads carry rounds as `Round.t` sexp strings, not JSON DTOs.
- Keep the `.mli` files synchronized with implementation changes.

## Change discipline

- Do not modify generated `_build/` contents or large audio assets.
- Preserve unrelated working-tree changes.
- Prefer small, focused patches and update `README.md` when CLI behavior or
  input format changes.
