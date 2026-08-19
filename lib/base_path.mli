open! Core

(** A validated base directory that other paths are derived from. *)
type t

(** Validate [base_dir] as a syntactically well-formed directory path (non-empty, no
    NUL byte) and wrap it as a [t]. Does not check that the directory exists. *)
val create : base_dir:string -> t Or_error.t

(** The underlying directory path. *)
val get_path : t -> string

(** [derive_path t ~path] joins [path] onto [t]'s directory. *)
val derive_path : t -> path:string -> string

(** Create [t]'s directory (and any missing parents) on disk if it doesn't already
    exist, then confirm the path really is a directory. *)
val instantiate : t -> unit Or_error.t