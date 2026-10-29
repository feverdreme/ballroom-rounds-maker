open! Core

let convert_command =
  Command.basic_or_error
    ~summary:"Convert a Round.t sexp file into a single concatenated mp3"
    (let%map_open.Command round_sexp_path =
       flag
         "-round-file"
         (required Filename_unix.arg_type)
         ~doc:"FILE sexp file describing the round (Round.t)"
     and output_mp3_path =
       flag "-output" (required Filename_unix.arg_type) ~doc:"FILE output mp3 path"
     and source_dir =
       flag
         "-source-path"
         (optional_with_default "." Filename_unix.arg_type)
         ~doc:"DIR base directory for file sources"
     and artifact_dir =
       flag
         "-artifact-path"
         (required Filename_unix.arg_type)
         ~doc:"DIR directory for intermediate artifacts (trimmed songs, breaks)"
     and ffmpeg_path =
       flag
         "-ffmpeg-path"
         (optional_with_default "ffmpeg" string)
         ~doc:"PATH path to the ffmpeg binary (default: ffmpeg)"
     in
     fun () ->
       let%bind.Or_error artifact_path =
         Rounds_lib.Base_path.create ~base_dir:artifact_dir
       in
       let%bind.Or_error source_path = Rounds_lib.Base_path.create ~base_dir:source_dir in
       let round = Rounds_lib.Round.read_from_file ~filepath:round_sexp_path in
       Rounds_lib.Converter.convert
         ~ffmpeg_path
         ~round
         ~source_path
         ~artifact_path
         ~output_path:output_mp3_path
         ())
;;

let () = Command_unix.run convert_command
