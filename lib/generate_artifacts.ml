open File_utils
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

(** Return true if the event description represents a break (prefixed with "<BREAK>"). *)
let is_break (events : string) : bool =
  String.starts_with ~prefix:"<BREAK>" events

(** Parse a break event string (e.g. "<BREAK> 30") and return the duration in seconds. *)
let extract_break (event : string) : int =
  match String.split_on_char ' ' event with
  | _ :: duration :: _ -> int_of_string duration
  | _ -> invalid_arg "extract_break: malformed break string"

(** Create an artifact from an event description: a silent break MP3 or a copied song file. *)
let create_artifact ?(ffmpeg_path="ffmpeg") (source_directory : string) (artifacts_directory : string) (description : string) : artifact =
  if is_break description then
    let break_duration = extract_break description in
    let break_filename = Printf.sprintf "%s/break_%d.mp3" artifacts_directory break_duration in
    if not (file_exists artifacts_directory break_filename) then
      generate_silence ~ffmpeg_path break_filename (seconds_to_ffmpeg_time break_duration);
    Break {path = break_filename; duration = break_duration}
  else
    let song_filename = normalize_filename description in
    let src = Filename.concat source_directory description in
    let dst = Filename.concat artifacts_directory song_filename in
    mkdir_p (Filename.dirname dst);
    copy_file ~src ~dst;
    Song {path = dst; config = empty_config}

(** Trim a song artifact to 90 seconds with fade effects. Breaks are returned unchanged. *)
let trim_artifact (artifact : artifact) : artifact =
  match artifact with
  | Break {path; duration} -> Break {path; duration}
  | Song {path; _} ->
    let trimmed_artifact_path = Filename.chop_extension path ^ ".trimmed.mp3" in
    ffmpeg_trim ~ffmpeg_path:"./ffmpeg" ~song_duration:90
      path
      trimmed_artifact_path;
    Song {path = trimmed_artifact_path; config = empty_config}

(** Concatenate a list of artifacts into a single MP3 at [output_path]. *)
let concat_artifacts ?(ffmpeg_path="ffmpeg") (artifacts_directory : string) (artifacts : artifact list) (output_path : string) : unit =
  let artifact_paths: string list = List.map (fun artifact -> match artifact with | Song {path; _} -> path | Break {path; _} -> path) artifacts in
  ffmpeg_concat ~ffmpeg_path artifact_paths artifacts_directory output_path
