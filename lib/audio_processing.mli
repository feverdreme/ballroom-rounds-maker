open! Core

(** Convert an integer number of seconds to an "HH:MM:SS" string for use in ffmpeg time arguments. *)
val seconds_to_ffmpeg_time : int -> string

(** Run a subprocess with the given argument list. If [~check] is true, raise on non-zero exit. *)
val run_command : ?check:bool -> string list -> unit

(** Trim [source] starting at [start] for [duration] seconds with configurable fade-in/out, writing to [dest]. *)
val ffmpeg_trim :
  ?ffmpeg_path:string ->
  start:int ->
  duration:int -> fade_in:int -> fade_out:int -> string -> string -> unit

(** Generate [break_duration] seconds of silence at [output_path]. Skips if the file already exists. *)
val generate_silence : ?ffmpeg_path:string -> string -> string -> unit

(** Resolve a relative path against the current working directory; absolute paths pass through unchanged. *)
val make_absolute : string -> string

(** Write an ffmpeg concat-demuxer file listing the absolute paths of [sourcelist]. *)
val create_concat_list : string list -> string -> unit

(** Concatenate audio files in [sourcelist] into a single MP3 at [output_path] using ffmpeg's concat demuxer. *)
val ffmpeg_concat :
  ?ffmpeg_path:string -> string list -> string -> string -> unit
