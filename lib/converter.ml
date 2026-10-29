open! Core
module Round = Rounds_model.Round

let map_path ~event ~(f : string -> string) =
  match event with
  | Round.Event.Song song ->
    Round.Event.Song
      { name = song.name
      ; dance = song.dance
      ; song_data = { song.song_data with filepath = f song.song_data.filepath }
      }
  | Break _ -> event
;;

let convert
  ?(ffmpeg_path = "ffmpeg")
  ~(round : Round.t)
  ~source_path
  ~artifact_path
  ~output_path
  ()
  =
  let%bind.Or_error () = Base_path.instantiate artifact_path in
  let artifact_filepath event =
    let path = Round.Event.to_string event |> Base_path.derive_path artifact_path in
    path ^ ".mp3"
  in
  (* Generate each artifact once, but preserve every event during playback. *)
  let unique_artifacts =
    List.stable_dedup round.events ~compare:(fun event1 event2 ->
      let path1 = Round.Event.to_string event1 in
      let path2 = Round.Event.to_string event2 in
      String.compare path1 path2)
  in
  let%bind.Or_error () =
    List.map unique_artifacts ~f:(fun event ->
      let output_path = artifact_filepath event in
      let source =
        map_path ~event ~f:(fun song_path ->
          Filename.concat (Base_path.get_path source_path) song_path)
      in
      print_endline output_path;
      match source with
      | Round.Event.Song song ->
        Ffmpeg.trim ~ffmpeg_path ~song:song.song_data ~output_path ()
      | Break break -> Ffmpeg.generate_break ~ffmpeg_path ~break ~output_path ())
    |> Or_error.combine_errors_unit
  in
  let artifacts = List.map round.events ~f:artifact_filepath in
  (* Concat everything *)
  Ffmpeg.ffmpeg_concat
    ~ffmpeg_path
    ~sources:artifacts
    ~artifacts_path:artifact_path
    ~output_path
    ()
;;
