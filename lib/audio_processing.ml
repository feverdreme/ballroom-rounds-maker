open! Core

(** Convert an integer number of seconds to an "HH:MM:SS" string for use in ffmpeg time arguments. *)
let seconds_to_ffmpeg_time (seconds : int) : string =
  let hours = seconds / 3600 in
  let minutes = seconds mod 3600 / 60 in
  let secs = seconds mod 60 in
  Printf.sprintf "%02d:%02d:%02d" hours minutes secs

(** Run a subprocess with the given argument list. If [~check] is true, raise on non-zero exit. *)
let run_command ?(check = false) (args : string list) : unit =
  match args with
  | [] -> invalid_arg "run_command: empty argument list"
  | prog :: _ ->
    let pid = Core_unix.fork_exec ~prog ~argv:args () in
    let status = Core_unix.waitpid pid in
    if check then
      match status with
      | Ok () -> ()
      | Error (`Exit_non_zero code) ->
        Printf.ksprintf failwith "Command failed with exit code %d" code
      | Error (`Signal signal) ->
        Printf.ksprintf failwith "Command killed by signal %s"
          (Signal.to_string signal)

(** Trim [source] starting at [start] for [duration] seconds with configurable fade-in/out, writing to [dest]. *)
let ffmpeg_trim ?(ffmpeg_path = "ffmpeg") ~(start : int) ~(duration : int)
    ~(fade_in : int) ~(fade_out : int) (source : string) (dest : string) : unit =
  let fade_out_start = duration - fade_out in
  let af = Printf.sprintf "afade=t=in:st=0:d=%d,afade=out:st=%d:d=%d" fade_in fade_out_start fade_out in
  run_command
    [ ffmpeg_path
    ; "-hide_banner"; "-loglevel"; "error"
    ; "-i"; source
    ; "-ss"; seconds_to_ffmpeg_time start
    ; "-t"; seconds_to_ffmpeg_time duration
    ; "-af"; af
    ; "-y"
    ; dest
    ]

(** Generate [break_duration] seconds of silence at [output_path]. Skips if the file already exists. *)
let generate_silence ?(ffmpeg_path = "ffmpeg") (output_path : string)
    (break_duration : string) : unit =
  if Sys_unix.file_exists_exn output_path then
    Printf.printf "%s already exists. Skipping...\n" output_path
  else
    run_command ~check:true
      [ ffmpeg_path
      ; "-hide_banner"; "-loglevel"; "error"
      ; "-f"; "lavfi"
      ; "-i"; "anullsrc=channel_layout=stereo:sample_rate=44100"
      ; "-t"; break_duration
      ; "-acodec"; "libmp3lame"
      ; output_path
      ]

(** Resolve a relative path against the current working directory; absolute paths pass through unchanged. *)
let make_absolute (path : string) : string =
  if Filename.is_relative path then Filename.concat (Sys_unix.getcwd ()) path
  else path

(** Write an ffmpeg concat-demuxer file listing the absolute paths of [sourcelist]. *)
let create_concat_list (sourcelist : string list) (concat_list_path : string) :
    unit =
  Out_channel.with_file concat_list_path ~f:(fun output_channel ->
      List.iter sourcelist ~f:(fun source ->
        Printf.fprintf output_channel "file %s\n" (make_absolute source)))

(** Concatenate audio files in [sourcelist] into a single MP3 at [output_path] using ffmpeg's concat demuxer. *)
let ffmpeg_concat ?(ffmpeg_path = "ffmpeg") (sourcelist : string list)
    (artifacts_path : string) (output_path : string) : unit =
  Printf.printf "Concatenating files...\n";
  Printf.printf "sourcelist=[%s]\n" (String.concat ~sep:"; " sourcelist);
  Printf.printf "artifacts_path=%s\n" artifacts_path;
  Printf.printf "output_path=%s\n" output_path;
  let concat_list_path = Filename.concat artifacts_path "concat_list.txt" in
  create_concat_list sourcelist concat_list_path;
  run_command ~check:true
    [ ffmpeg_path
    ; "-hide_banner"; "-loglevel"; "error"
    ; "-f"; "concat"
    ; "-safe"; "0"
    ; "-i"; concat_list_path
    ; "-c:a"; "libmp3lame"
    ; "-b:a"; "192k"
    ; "-y"
    ; output_path
    ]
