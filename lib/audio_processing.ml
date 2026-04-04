let seconds_to_ffmpeg_time (seconds : int) : string =
  let hours = seconds / 3600 in
  let minutes = seconds mod 3600 / 60 in
  let secs = seconds mod 60 in
  Printf.sprintf "%02d:%02d:%02d" hours minutes secs

let run_command ?(check = false) (args : string list) : unit =
  if List.is_empty args then invalid_arg "run_command: empty argument list" else
  let prog = List.hd args in
  let args_array = Array.of_list args in
  let pid =
    Unix.create_process prog args_array Unix.stdin Unix.stdout Unix.stderr
  in
  let _, status = Unix.waitpid [] pid in
  if check then
    match status with
    | Unix.WEXITED 0 -> ()
    | Unix.WEXITED code ->
      Printf.ksprintf failwith "Command failed with exit code %d" code
    | Unix.WSIGNALED signal ->
      Printf.ksprintf failwith "Command killed by signal %d" signal
    | Unix.WSTOPPED signal ->
      Printf.ksprintf failwith "Command stopped by signal %d" signal

let ffmpeg_trim ?(ffmpeg_path = "ffmpeg") ?(song_duration = 90)
    (source : string) (dest : string) : unit =
  let ffmpeg_seconds = seconds_to_ffmpeg_time song_duration in
  run_command
    [ ffmpeg_path
    ; "-hide_banner"; "-loglevel"; "error"
    ; "-i"; source
    ; "-ss"; "00:00:00"
    ; "-t"; ffmpeg_seconds
    ; "-af"; "afade=t=in:st=0:d=5,afade=out:st=85:d=5"
    ; "-y"
    ; dest
    ]

let generate_silence ?(ffmpeg_path = "ffmpeg") (output_path : string)
    (break_duration : string) : unit =
  if Sys.file_exists output_path then
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

let make_absolute (path : string) : string =
  if Filename.is_relative path then Filename.concat (Sys.getcwd ()) path
  else path

let create_concat_list (sourcelist : string list) (concat_list_path : string) :
    unit =
  let output_channel = open_out concat_list_path in
  Fun.protect ~finally:(fun () -> close_out output_channel) (fun () ->
      List.iter (fun source ->
        Printf.fprintf output_channel "file %s\n" (make_absolute source)) sourcelist)

let ffmpeg_concat ?(ffmpeg_path = "ffmpeg") (sourcelist : string list)
    (artifacts_path : string) (output_path : string) : unit =
  Printf.printf "Concatenating files...\n";
  Printf.printf "sourcelist=[%s]\n" (String.concat "; " sourcelist);
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
