open! Core

(** Recursively create directories along [path], like [mkdir -p]. *)
val mkdir_p : string -> unit

(** Copy a file from [src] to [dst] using the system [cp] command. *)
val copy_file : src:string -> dst:string -> unit

(** Normalize a filename by stripping apostrophes, spaces, and replacing hyphens with underscores. *)
val normalize_filename : string -> string

(** Return true if [filename] exists within [directory]. *)
val file_exists : string -> string -> bool

(** Return true if every event name in [events] corresponds to an existing file in [directory]. *)
val check_event_files_exist : string -> string list -> bool