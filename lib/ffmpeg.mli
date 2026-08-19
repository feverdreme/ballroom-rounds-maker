open! Core

val trim
  :  ?ffmpeg_path:string
  -> song:Round.Song.t
  -> output_path:string
  -> unit
  -> unit Or_error.t

(** Generate [break_duration] seconds of silence at [output_path]. Skips if the file
    already exists. *)
val generate_break
  :  ?ffmpeg_path:string
  -> break:Round.Break.t
  -> output_path:string
  -> unit
  -> unit Or_error.t

val ffmpeg_concat
  :  ?ffmpeg_path:string
  -> sources:string list
  -> artifacts_path:Base_path.t
  -> output_path:string
  -> unit
  -> unit Or_error.t
