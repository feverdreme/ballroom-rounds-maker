---
name: rounds
description: Create, edit, validate, and produce ballroom competition rounds in this repo, and download source songs from Spotify. Use when asked to make or change a round, build a heat, add songs or breaks, download music for rounds, or render a round to MP3.
---

# Rounds

A round is a `Round.t` sexp file: an ordered list of songs and breaks that the
converter renders into one MP3. Read `README.md` for the full format and flags
if anything below is unclear.

## Prefer the MCP tools

If the `rounds` MCP tools are available (`list_rounds`, `list_songs`,
`get_round`, `save_round`, `delete_round`, `download_songs`, `produce_round`),
use them instead of the CLI. They validate rounds before writing and confine
every read and write to the configured directories. The rest of this skill is
the CLI fallback, and its rules apply either way.

## Directories

The usual layout, relative to the repo root:

| Purpose | Directory |
| --- | --- |
| Round sexp files | `rounds/` |
| Source audio | `hellrounds_source/` |
| Intermediate artifacts | `hellrounds_source_artifacts/` |
| Produced MP3s | `rounds_output/` |

If the user names other directories, use theirs. If a directory you need is
missing and the user has not named one, ask rather than guessing.

## Round format

```lisp
((name champ_smooth_1heat_oct29)
 (events
  ((Song
    (song_data
     ((filepath "Smooth/Waltz/Some Song.mp3")
      (duration 90) (fade_in 0) (fade_out 5)))
    (name ()) (dance ()))
   (Break ((duration 10))))))
```

- `filepath` is relative to the source directory. Quote it when it contains
  spaces or punctuation.
- `duration`, `fade_in`, `fade_out`, and break `duration` are whole seconds.
- `name` and `dance` are `()` or `(Some_value)`; follow the style of existing
  rounds in `rounds/`.
- A heat that repeats a song repeats the whole `Song` event. Repeats are cheap:
  the converter renders each unique song or break once.

Before saving a round, check every event:

1. Each song's `filepath` exists under the source directory. List candidates
   with `find hellrounds_source -type f \( -name '*.mp3' -o -name '*.wav' -o
   -name '*.m4a' \)` and copy paths exactly.
2. `fade_in + fade_out <= duration` for each song.
3. Every break duration is positive.
4. The whole file parses as a sexp with balanced parentheses.

Match the existing rounds for conventions such as song length, break lengths
between dances versus between heats, and file naming
(`<level>_<style>_<n>heat(s)_<date>.sexp`). Read one or two similar rounds
first.

## Download songs

```bash
dune exec bin/download_spotify.exe -- -source-path hellrounds_source <spotify_url>...
```

- Pass several URLs in one call when downloading a batch.
- Downloads land at the top of the source directory as
  `<artists> - <title>.mp3`. Rounds usually reference songs under
  `<Style>/<Dance>/`; ask before moving downloaded files into that structure.
- Never put Spotify client IDs or secrets on the command line. Credentials come
  from `~/.spotdl/config.json`.

## Produce a round

```bash
dune exec bin/main.exe -- \
  -round-file rounds/<round>.sexp \
  -output rounds_output/<round>.mp3 \
  -artifact-path hellrounds_source_artifacts \
  -source-path hellrounds_source
```

Confirm the output MP3 exists afterwards. If ffmpeg fails, report its error
rather than retrying with changed flags.

## Boundaries

- Write round files only in the rounds directory and produced MP3s only in the
  output directory.
- Never modify, rename, or delete source audio unless the user asks.
- Ask before overwriting or deleting an existing round.
- Do not hand-edit artifacts; delete the stale artifact and re-run the
  converter if one is wrong.
