open! Core

let prepend_base_dir ~base_path ~event =
  match event with
  | Rounds_lib.Round.Event.Song song ->
    let%bind.Or_error song_data = Rounds_lib.Round.Song.create
      ~filepath:(Filename.concat (Rounds_lib.Base_path.get_path base_path) song.song.filepath)
      ~duration:song.song.duration
      ~fade_in:song.song.fade_in
      ~fade_out:song.song.fade_out in
    Rounds_lib.Round.Event.Song {song=song_data; name=song.name; dance=song.dance} |> Or_error.return
  | Break _ -> Ok event
;;

let convert_round
  ~(ffmpeg_path : string)
  ~(round_sexp_path : string)
  ~(output_mp3_path : string)
  ~(source_path : Rounds_lib.Base_path.t)
  ~(artifact_path : Rounds_lib.Base_path.t)
  : unit Or_error.t
  =
  let round = Rounds_lib.Round.read_from_file ~filepath:round_sexp_path in
  let%bind.Or_error () = Rounds_lib.Base_path.instantiate artifact_path in
  let%bind.Or_error sources =
    List.mapi round.events ~f:(fun index (event : Rounds_lib.Round.Event.t) ->
      let%bind.Or_error event = prepend_base_dir ~base_path:source_path ~event in
      match event with
      | Song { song; _ } ->
        let output_path =
          Rounds_lib.Base_path.derive_path
            artifact_path
            ~path:(Printf.sprintf "%d_trimmed.mp3" index)
        in
        let%map.Or_error () = Rounds_lib.Ffmpeg.trim ~ffmpeg_path ~song ~output_path () in
        output_path
      | Break break ->
        let output_path =
          Rounds_lib.Base_path.derive_path
            artifact_path
            ~path:(Printf.sprintf "break_%d.mp3" break.duration)
        in
        let%map.Or_error () =
          Rounds_lib.Ffmpeg.generate_break ~ffmpeg_path ~break ~output_path ()
        in
        output_path)
    |> Or_error.all
  in
  Rounds_lib.Ffmpeg.ffmpeg_concat
    ~ffmpeg_path
    ~sources
    ~artifacts_path:(Rounds_lib.Base_path.get_path artifact_path)
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
       convert_round
         ~ffmpeg_path
         ~round_sexp_path
         ~output_mp3_path
         ~source_path
         ~artifact_path)
;;

let () = Command_unix.run convert_command
