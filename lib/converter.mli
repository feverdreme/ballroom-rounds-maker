open! Core
module Round = Rounds_model.Round

(** Trim each unique song and generate each unique break of [round] into [artifact_path],
    then concatenate the artifacts in event order into [output_path]. Song filepaths are
    resolved against [source_path]. *)
val convert
  :  ?ffmpeg_path:string
  -> round:Round.t
  -> source_path:Base_path.t
  -> artifact_path:Base_path.t
  -> output_path:string
  -> unit
  -> unit Or_error.t
