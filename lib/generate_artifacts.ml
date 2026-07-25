open! Core
open File_operations
open Audio_processing

(** Per-song audio configuration. All times in seconds. None means "use the default". *)
type song_config = {
  start: int option;
  end_at: int option;
  duration: int option;
  fade_in: int option;
  fade_out: int option;
}

(** Global defaults from [defaults] section. *)
type defaults = {
  song_duration: int;
  break_duration: int;
  fade_in: int;
  fade_out: int;
}

(** The artifact monad tracks a physical file with which you can do operations on through the artifacts API.
    Applying artifact operations translates to performing certain (traceable) steps on disk. *)
type artifact = Break of {path: string; duration: int} | Song of {path: string; config: song_config}

(** A parsed round. *)
type round = { name: string; entries: artifact list }

(** A complete parsed .rounds file. *)
type rounds_file = { defaults: defaults; rounds: round list }

let empty_config = { start = None; end_at = None; duration = None; fade_in = None; fade_out = None }

let default_defaults = { song_duration = 90; break_duration = 10; fade_in = 5; fade_out = 5 }

(** Resolve a song_config against defaults, producing concrete values for start, duration, fade_in, fade_out. *)
let resolve_config (defaults : defaults) (config : song_config) : int * int * int * int =
  let start = Option.value ~default:0 config.start in
  let duration = match config.duration, config.end_at with
    | Some d, Some e ->
      if start + d <> e then
        invalid_arg (Printf.sprintf "resolve_config: start (%d) + duration (%d) = %d, but end (%d) disagrees" start d (start + d) e)
      else d
    | Some d, None -> d
    | None, Some e -> e - start
    | None, None -> defaults.song_duration
  in
  let fade_in = Option.value ~default:defaults.fade_in config.fade_in in
  let fade_out = Option.value ~default:defaults.fade_out config.fade_out in
  (start, duration, fade_in, fade_out)

(** Create an artifact from a parsed entry: generate silence for breaks, copy song files. *)
let create_artifact ?(ffmpeg_path="ffmpeg") (source_directory : string) (artifacts_directory : string) (defaults : defaults) (artifact : artifact) : artifact =
  match artifact with
  | Break {duration; _} ->
    let break_dur = if duration = 0 then defaults.break_duration else duration in
    let break_filename = Printf.sprintf "%s/break_%d.mp3" artifacts_directory break_dur in
    if not (Sys_unix.file_exists_exn break_filename) then
      generate_silence ~ffmpeg_path break_filename (seconds_to_ffmpeg_time break_dur);
    Break {path = break_filename; duration = break_dur}
  | Song {path; config} ->
    let song_filename = normalize_filename path in
    let src = Filename.concat source_directory path in
    let dst = Filename.concat artifacts_directory song_filename in
    mkdir_p (Filename.dirname dst);
    copy_file ~src ~dst;
    Song {path = dst; config}

(** Trim a song artifact with configurable timing. Breaks are returned unchanged. *)
let trim_artifact ?(ffmpeg_path="ffmpeg") (defaults : defaults) (artifact : artifact) : artifact =
  match artifact with
  | Break _ -> artifact
  | Song {path; config} ->
    let (start, duration, fade_in, fade_out) = resolve_config defaults config in
    let trimmed_artifact_path = Filename.chop_extension path ^ ".trimmed.mp3" in
    ffmpeg_trim ~ffmpeg_path ~start ~duration ~fade_in ~fade_out
      path
      trimmed_artifact_path;
    Song {path = trimmed_artifact_path; config}

(** Concatenate a list of artifacts into a single MP3 at [output_path]. *)
let concat_artifacts ?(ffmpeg_path="ffmpeg") (artifacts_directory : string) (artifacts : artifact list) (output_path : string) : unit =
  let artifact_paths = List.map ~f:(fun artifact -> match artifact with | Song {path; _} -> path | Break {path; _} -> path) artifacts in
  ffmpeg_concat ~ffmpeg_path artifact_paths artifacts_directory output_path
