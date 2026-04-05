open Ballroom_rounds_maker_lib.Generate_artifacts
open Ballroom_rounds_maker_lib.Parse_rounds

type build_config = {
  source_directory : string;
  artifacts_directory : string;
  output_directory : string;
  ffmpeg_path : string;
}

let default_build_config = {
  source_directory = "hellrounds_source";
  artifacts_directory = "hellrounds_source_artifacts";
  output_directory = "rounds_output";
  ffmpeg_path = "./ffmpeg";
}

let parse_args () : build_config * string =
  let rounds_file_path = ref "" in
  let config = ref default_build_config in
  let speclist = [
    ("--source-dir", Arg.String (fun s -> config := { !config with source_directory = s }),
     "Source directory for audio files (default: hellrounds_source)");
    ("--artifacts-dir", Arg.String (fun s -> config := { !config with artifacts_directory = s }),
     "Artifacts directory for intermediate files (default: hellrounds_source_artifacts)");
    ("--output-dir", Arg.String (fun s -> config := { !config with output_directory = s }),
     "Output directory for final rounds (default: rounds_output)");
    ("--ffmpeg-path", Arg.String (fun s -> config := { !config with ffmpeg_path = s }),
     "Path to ffmpeg binary (default: ./ffmpeg)");
  ] in
  let usage = Printf.sprintf "Usage: %s [options] <rounds_file>" Sys.argv.(0) in
  Arg.parse speclist (fun anon -> rounds_file_path := anon) usage;
  if !rounds_file_path = "" then begin
    Arg.usage speclist usage;
    exit 1
  end;
  (!config, !rounds_file_path)

let process_round (config : build_config) (defaults : defaults) (round : round) : unit =
  Ballroom_rounds_maker_lib.File_utils.mkdir_p config.output_directory;
  let output_name = Filename.concat config.output_directory (round.name ^ ".mp3") in
  Printf.printf "Processing round: %s -> %s\n" round.name output_name;
  flush_all (); (* Ensure all output buffers are flushed before intensive processing *)
  let artifacts = List.map
    (create_artifact ~ffmpeg_path:config.ffmpeg_path config.source_directory config.artifacts_directory defaults)
    round.entries in
  let trimmed = List.map
    (trim_artifact ~ffmpeg_path:config.ffmpeg_path defaults) artifacts in
  concat_artifacts ~ffmpeg_path:config.ffmpeg_path config.artifacts_directory trimmed output_name

let () =
  let (config, rounds_file_path) = parse_args () in
  let rounds_file = parse_file rounds_file_path in
  Printf.printf "Parsed %d round(s) with defaults: song_duration=%d, break_duration=%d, fade_in=%d, fade_out=%d\n"
    (List.length rounds_file.rounds)
    rounds_file.defaults.song_duration
    rounds_file.defaults.break_duration
    rounds_file.defaults.fade_in
    rounds_file.defaults.fade_out;
  List.iter (process_round config rounds_file.defaults) rounds_file.rounds
