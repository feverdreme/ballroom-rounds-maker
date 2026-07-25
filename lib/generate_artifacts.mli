open! Core

(** Per-song audio configuration. All times in seconds. None means "use the default". *)
type song_config = {
  start : int option;
  end_at : int option;
  duration : int option;
  fade_in : int option;
  fade_out : int option;
}

(** Global defaults from [defaults] section. *)
type defaults = {
  song_duration : int;
  break_duration : int;
  fade_in : int;
  fade_out : int;
}

(** The artifact monad tracks a physical file with which you can do operations on through the artifacts API.
    Applying artifact operations translates to performing certain (traceable) steps on disk. *)
type artifact =
    Break of { path : string; duration : int; }
  | Song of { path : string; config : song_config; }

(** A parsed round. *)
type round = { name : string; entries : artifact list; }

(** A complete parsed .rounds file. *)
type rounds_file = { defaults : defaults; rounds : round list; }
val empty_config : song_config
val default_defaults : defaults

(** Resolve a song_config against defaults, producing concrete values for start, duration, fade_in, fade_out. *)
val resolve_config : defaults -> song_config -> int * int * int * int

(** Create an artifact from a parsed entry: generate silence for breaks, copy song files. *)
val create_artifact :
  ?ffmpeg_path:string -> string -> string -> defaults -> artifact -> artifact

(** Trim a song artifact with configurable timing. Breaks are returned unchanged. *)
val trim_artifact : ?ffmpeg_path:string -> defaults -> artifact -> artifact

(** Concatenate a list of artifacts into a single MP3 at [output_path]. *)
val concat_artifacts :
  ?ffmpeg_path:string -> string -> artifact list -> string -> unit
