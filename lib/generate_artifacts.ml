open File_utils
open Audio_processing

type artifact = Break of {path: string; duration: int} | Song of {path: string}
(* The artifact monad tracks a physical file with which you can do operations on through the artifacts API.
  Applying artifact operations translates to performating certain (traceable) steps on disk.
*)

let is_break (events : string) : bool =
  String.starts_with ~prefix:"<BREAK>" events

let extract_break (event : string) : int =
  match String.split_on_char ' ' event with
  | _ :: duration :: _ -> int_of_string duration
  | _ -> invalid_arg "extract_break: malformed break string"

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
    Song {path = dst}

let trim_artifact (artifact : artifact) : artifact =
  match artifact with
  | Break {path; duration} -> Break {path; duration}
  | Song {path} ->
    let trimmed_artifact_path = Filename.chop_extension path ^ ".trimmed.mp3" in
    ffmpeg_trim ~ffmpeg_path:"./ffmpeg" ~song_duration:90
      path
      trimmed_artifact_path;
    Song {path = trimmed_artifact_path}

let concat_artifacts ?(ffmpeg_path="ffmpeg") (artifacts_directory : string) (artifacts : artifact list) (output_path : string) : unit =
  let artifact_paths: string list = List.map (fun artifact -> match artifact with | Song {path} -> path | Break {path; _} -> path) artifacts in
  ffmpeg_concat ~ffmpeg_path artifact_paths artifacts_directory output_path