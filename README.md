# Ballroom Rounds Maker

An OCaml CLI tool that assembles ballroom dance competition "rounds" -- single
MP3 files composed of multiple songs (one per dance style) separated by
configurable silence breaks. A round is described as a `Round.t` value
serialized to a sexp file. The tool orchestrates **ffmpeg** to trim each song,
generate silence for breaks, and concatenate everything into one output file.

## Prerequisites

- **OCaml** (with opam)
- **Dune 3**
- **opam packages:** `core`, `core_unix`, `unix`, `ppx_jane`, `async`,
  `bonsai`, `bonsai_web`, `js_of_ocaml`, `cohttp-async`, and `yojson`
- **ffmpeg** -- must be on your `PATH`, or pass `-ffmpeg-path` to point at a
  specific binary
- **spotDL** (optional, for Spotify downloads) -- requires Python 3.10--3.14
  and ffmpeg 4.2 or newer. Install it with `pip3 install spotdl`.

Install OCaml dependencies:

```bash
opam install core core_unix ppx_jane async bonsai bonsai_web js_of_ocaml cohttp-async yojson
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
    (song_data
     ((filepath "Standard/Waltz/Don't Be So Shy (Slow Waltz 29).mp3")
      (duration 90) (fade_in 5) (fade_out 5)))
    (name ()) (dance ()))
   (Break ((duration 10)))
   (Song
    (song_data
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

1. **Deduplicate artifact generation** -- events are stable-deduped by their string
   representation (song path + fade/duration, or break duration) so repeated
   entries reuse the same artifact.
2. **Create + trim artifacts** -- each unique `Song` is trimmed from
   `-source-path` with its configured duration, fade-in, and fade-out via
   ffmpeg; each unique `Break` becomes a generated silent MP3 (skipped if it
   already exists). Artifact filenames are derived from the event's string
   representation under `-artifact-path`.
3. **Concatenate** -- artifact paths are written in the original event order,
   including every repeated song and break, to an ffmpeg concat demuxer list.
   ffmpeg produces the final MP3 (192 kbps) at `-output`.

## Usage

### Build

```bash
dune build
```

### Test

```bash
dune runtest
```

The spotDL test downloads its documented sample track into a temporary
directory, verifies that the resulting MP3 is nonempty, and then removes it.
It requires spotDL, ffmpeg, network access, and writes progress logs as it runs.
The converter regression test uses a stub in place of ffmpeg to check that its
concat list preserves repeated songs and breaks in order; it does not encode audio.

### Run

#### Web editor

The web editor has the same round-authoring capabilities as the terminal UI:
create or open a round, add and edit songs and breaks, reorder or delete
events, rename the round, and save it as a sexp file.

```bash
dune exec bin/web.exe
```

Then open <http://127.0.0.1:8080>. The server runs only on the local loopback
interface. Enter the directory where round sexp files should live and the
directory containing the source audio. The browser does not receive access to
the filesystem itself; it exchanges S-expression messages with the local OCaml
server, which performs the reads and writes.

The file lists are refreshed on demand. Opening the rounds dashboard rescans
the rounds directory for sexp files, and opening the Add/Edit Song dialog
rescans the source directory for supported audio files (`.mp3`, `.wav`, and
`.m4a`). Changes made outside the editor therefore appear the next time the
corresponding view is opened; the server does not continuously watch or poll
either directory.

Selecting an audio file collapses the search into a selected-song card. Use
**Change song** to reopen and refresh the search; the current song appears first
and is marked as selected, followed by the other matching files.

Use a different port if needed:

```bash
dune exec bin/web.exe -- -port 9090
```

The web editor creates and edits round descriptions. Use the converter below
to generate the concatenated MP3.

#### Terminal editor

```bash
dune exec bin/tui.exe
```

#### MP3 converter

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

#### MCP server for agents

`mcp` serves a [Model Context Protocol](https://modelcontextprotocol.io) server
over stdio so coding agents can manage rounds, download songs, and produce
round MP3s through typed tools instead of shell commands:

| Tool | Effect |
| --- | --- |
| `list_rounds` | List round sexp files with names and event counts. |
| `list_songs` | List audio files in the source directory. |
| `get_round` | Return a round as a `Round.t` sexp. |
| `save_round` | Validate and save a `Round.t` sexp. |
| `delete_round` | Delete a round sexp file. |
| `download_songs` | Download Spotify URLs into the source directory with spotDL. |
| `produce_round` | Render a saved round to `<output-path>/<round path>.mp3`. |

Rounds travel as `Round.t` sexp strings, the same format as the files.
`save_round` rejects unparseable rounds, songs whose fades exceed their
duration, non-positive breaks, and song paths missing from the source
directory; without an explicit `path` it also refuses to overwrite an existing
round. Round paths must be relative and cannot contain `.` or `..` segments.

Every directory is fixed when the server starts, so the agent cannot read or
write outside them. Use absolute paths, because the agent decides the working
directory. To register the server with Claude Code:

```bash
dune build
claude mcp add rounds -- "$PWD/_build/default/bin/mcp.exe" \
  -rounds-path "$PWD/rounds" \
  -source-path "$PWD/hellrounds_source" \
  -artifact-path "$PWD/hellrounds_source_artifacts" \
  -output-path "$PWD/rounds_output"
```

The optional flags `-ffmpeg-path`, `-spotdl-path`, `-no-spotdl-config`, and
`-use-official-spotify-api` behave like the converter and downloader flags.
Spotify credentials are read only from the spotDL config file, so they never
appear in tool calls. ffmpeg and spotDL output goes to the server's stderr, so
it cannot corrupt the protocol stream on stdout. Tool calls run one at a time;
`produce_round` and `download_songs` block until ffmpeg or spotDL finishes.

#### Download source MP3s with spotDL

`download_spotify` accepts one or more Spotify track, album, playlist, or
artist URLs. It creates the source directory when needed and downloads MP3s
there using the filename format `<artists> - <title>.mp3`:

```bash
dune exec bin/download_spotify.exe -- \
  -source-path hellrounds_source \
  https://open.spotify.com/track/0VjIjW4GlUZAMYd2vXMi3b
```

To use your Spotify developer application, pass its client ID and secret
together. `-use-official-spotify-api` tells spotDL to use Spotify's official
Web API client:

```bash
dune exec bin/download_spotify.exe -- \
  -source-path hellrounds_source \
  -spotify-client-id "$SPOTIFY_CLIENT_ID" \
  -spotify-client-secret "$SPOTIFY_CLIENT_SECRET" \
  -use-official-spotify-api \
  https://open.spotify.com/track/0VjIjW4GlUZAMYd2vXMi3b
```

Pass multiple URLs to download them in one spotDL invocation. If spotDL is not
on `PATH`, use `-spotdl-path <path_to_spotdl>`. The command forwards credentials
directly to spotDL, so avoid literal secrets in your shell history.

By default, the command passes spotDL's `--config` flag, which loads spotDL's
own config file (usually `~/.spotdl/config.json`). spotDL cannot load a config
from another path, and it fails when that file is missing; pass
`-no-spotdl-config` to skip it. Generate a starting file with `spotdl --generate-config`,
then set `client_id`, `client_secret`, and `use_official_api` there.
