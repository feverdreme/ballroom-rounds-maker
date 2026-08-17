open! Core

let convert_round
  ~(ffmpeg_path : string)
  ~(round_sexp_path : string)
  ~(output_mp3_path : string)
  : unit Or_error.t
  =
  let round = Rounds_lib.Round.read_from_file ~filepath:round_sexp_path in
  let artifacts_dir = Filename.chop_extension output_mp3_path ^ "_artifacts" in
  Core_unix.mkdir_p ~perm:0o755 artifacts_dir;
  let%bind.Or_error sources =
    List.mapi round.events ~f:(fun index (event : Rounds_lib.Round.Event.t) ->
      match event with
      | Song { song; _ } ->
        let output_path =
          Filename.concat artifacts_dir (Printf.sprintf "%d_trimmed.mp3" index)
        in
        let%map.Or_error () = Rounds_lib.Ffmpeg.trim ~ffmpeg_path ~song ~output_path () in
        output_path
      | Break break ->
        let output_path =
          Filename.concat
            artifacts_dir
            (Printf.sprintf "break_%d.mp3" break.duration)
        in
        let%map.Or_error () = Rounds_lib.Ffmpeg.generate_break ~ffmpeg_path ~break ~output_path () in
        output_path)
    |> Or_error.all
  in
  Rounds_lib.Ffmpeg.ffmpeg_concat
    ~ffmpeg_path
    ~sources
    ~artifacts_path:artifacts_dir
    ~output_path:output_mp3_path
    ()
;;

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
     and ffmpeg_path =
       flag
         "-ffmpeg-path"
         (optional_with_default "ffmpeg" string)
         ~doc:"PATH path to the ffmpeg binary (default: ffmpeg)"
     in
     fun () -> convert_round ~ffmpeg_path ~round_sexp_path ~output_mp3_path)
;;

let () = Command_unix.run convert_command
