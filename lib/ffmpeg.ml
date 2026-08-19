open! Core

let seconds_to_ffmpeg_time ~seconds =
  let hours = seconds / 3600 in
  let minutes = seconds mod 3600 / 60 in
  let secs = seconds mod 60 in
  Printf.sprintf "%02d:%02d:%02d" hours minutes secs
;;

(** Trim [source] starting at [start] for [duration] seconds with configurable
    fade-in/out, writing to [dest]. *)
let trim ?(ffmpeg_path = "ffmpeg") ~(song : Round.Song.t) ~output_path () =
  let fade_out_start = song.duration - song.fade_out in
  let af =
    Printf.sprintf
      "afade=t=in:st=0:d=%d,afade=out:st=%d:d=%d"
      song.fade_in
      fade_out_start
      song.fade_out
  in
  let start_time = seconds_to_ffmpeg_time ~seconds:0 in
  let duration_time = seconds_to_ffmpeg_time ~seconds:song.duration in
  let source = Filename.quote song.filepath in
  let output_path = Filename.quote output_path in
  let af = Filename.quote af in
  match
    Sys_unix.command
      [%string
        "%{ffmpeg_path} -hide_banner -loglevel error -i %{source} -ss %{start_time} -t \
         %{duration_time} -af %{af} -y %{output_path}"]
  with
  | 0 -> Ok ()
  | return_code -> Or_error.error_s [%message (return_code : int)]
;;

(** Generate [break_duration] seconds of silence at [output_path]. Skips if the file
    already exists. *)
let generate_break
  ?(ffmpeg_path = "ffmpeg")
  ~(break : Round.Break.t)
  ~(output_path : string)
  ()
  =
  if Sys_unix.file_exists_exn output_path
  then Printf.printf "%s already exists. Skipping...\n" output_path |> Or_error.return
  else (
    match
      Sys_unix.command
        [%string
          "%{ffmpeg_path} -hide_banner -loglevel error -f lavfi -i \
           anullsrc=channel_layout=stereo:sample_rate=44100 -t %{break.duration#Int} \
           -acodec libmp3lame %{output_path}"]
    with
    | 0 -> Ok ()
    | return_code -> Or_error.error_s [%message (return_code : int)])
;;

(** Resolve a relative path against the current working directory; absolute paths pass
    through unchanged. *)
let make_absolute (path : string) : string =
  if Filename.is_relative path then Filename.concat (Sys_unix.getcwd ()) path else path
;;

(** Write an ffmpeg concat-demuxer file listing the absolute paths of [sourcelist]. *)
let create_concat_list ~sources ~output_path : unit =
  Out_channel.with_file output_path ~f:(fun output_channel ->
    List.iter sources ~f:(fun source ->
      Printf.fprintf output_channel "file %s\n" (make_absolute source)))
;;

let ffmpeg_concat ?(ffmpeg_path = "ffmpeg") ~sources ~artifacts_path ~output_path () =
  Printf.printf "Concatenating files...\n";
  Printf.printf "sourcelist=[%s]\n" (String.concat ~sep:"; " sources);
  Printf.printf "artifacts_path=%s\n" artifacts_path;
  Printf.printf "output_path=%s\n" output_path;
  let concat_list_path = Filename.concat artifacts_path "concat_list.txt" in
  create_concat_list ~sources ~output_path:concat_list_path;
  match
    Sys_unix.command
      [%string
        "%{ffmpeg_path} -hide_banner -loglevel error -f concat -safe 0 -i \
         %{concat_list_path} -c:a libmp3lame -b:a 192k -y %{output_path}"]
  with
  | 0 -> Ok ()
  | return_code -> Or_error.error_s [%message (return_code : int)]
;;
