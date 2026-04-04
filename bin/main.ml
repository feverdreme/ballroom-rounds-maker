open Ballroom_rounds_maker_lib.Generate_artifacts
open Ballroom_rounds_maker_lib.Parse_rounds

let source_directory = "hellrounds_source"
let artifacts_directory = "hellrounds_source_artifacts"
let output_directory = "rounds_output"

let process_round (defaults : defaults) (round : round) : unit =
  Ballroom_rounds_maker_lib.File_utils.mkdir_p output_directory;
  let output_name = Filename.concat output_directory (round.name ^ ".mp3") in
  Printf.printf "Processing round: %s -> %s\n" round.name output_name;
  flush_all (); (* Ensure all output buffers are flushed before intensive processing *)
  let artifacts = List.map
    (create_artifact ~ffmpeg_path:"./ffmpeg" source_directory artifacts_directory defaults)
    round.entries in
  let trimmed = List.map
    (trim_artifact ~ffmpeg_path:"./ffmpeg" defaults) artifacts in
  concat_artifacts ~ffmpeg_path:"./ffmpeg" artifacts_directory trimmed output_name

let () =
  if Array.length Sys.argv < 2 then begin
    Printf.eprintf "Usage: %s <rounds_file>\n" Sys.argv.(0);
    exit 1
  end;
  let rounds_file = parse_file Sys.argv.(1) in
  Printf.printf "Parsed %d round(s) with defaults: song_duration=%d, break_duration=%d, fade_in=%d, fade_out=%d\n"
    (List.length rounds_file.rounds)
    rounds_file.defaults.song_duration
    rounds_file.defaults.break_duration
    rounds_file.defaults.fade_in
    rounds_file.defaults.fade_out;
  List.iter (process_round rounds_file.defaults) rounds_file.rounds
