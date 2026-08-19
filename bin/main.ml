open! Core

let map_path ~event ~(f : string -> string) =
  match event with
  | Rounds_lib.Round.Event.Song song ->
    Rounds_lib.Round.Event.Song
      { name = song.name
      ; dance = song.dance
      ; song = { song.song with filepath = f song.song.filepath }
      }
  | Break _ -> event
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
  (* Deduplicate the filenames *)
  let unique_artifacts =
    List.stable_dedup round.events ~compare:(fun event1 event2 ->
      let path1 = Rounds_lib.Round.Event.to_string event1 in
      let path2 = Rounds_lib.Round.Event.to_string event2 in
      String.compare path1 path2)
  in
  let%bind.Or_error artifacts =
    List.map unique_artifacts ~f:(fun event ->
      let output_path =
        Rounds_lib.Round.Event.to_string event
        |> Rounds_lib.Base_path.derive_path artifact_path
      in
      let source =
        map_path ~event ~f:(fun song_path ->
          Filename.concat (Rounds_lib.Base_path.get_path source_path) song_path)
      in
      let output_path = [%string "%{output_path}.mp3"] in
      print_endline output_path;
      let%bind.Or_error () =
        match source with
        | Rounds_lib.Round.Event.Song song ->
          Rounds_lib.Ffmpeg.trim ~ffmpeg_path ~song:song.song ~output_path ()
        | Break break ->
          Rounds_lib.Ffmpeg.generate_break ~ffmpeg_path ~break ~output_path ()
      in
      Ok output_path)
    |> Or_error.combine_errors
  in
  (* Concat everything *)
  Rounds_lib.Ffmpeg.ffmpeg_concat
    ~ffmpeg_path
    ~sources:artifacts
    ~artifacts_path:artifact_path
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
