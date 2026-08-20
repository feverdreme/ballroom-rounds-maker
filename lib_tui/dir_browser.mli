open! Core

(** Recursively lists files under [root] whose extension (case-insensitive) is one of
    [extensions]. Paths are returned relative to [root], suitable for storing directly as
    [Rounds_lib.Round.Song.filepath]. *)
val list_files_by_extension
  :  root:string
  -> extensions:string list
  -> string list Or_error.t

(** Same as [list_files_by_extension], but returns absolute paths. *)
val list_files_by_extension_abs
  :  root:string
  -> extensions:string list
  -> string list Or_error.t

(** Derives a filesystem-safe basename from a round's [name] field. *)
val sanitize_filename : string -> string

(** Given a partially-typed path, lists filesystem entries in its directory that match
    the last path segment as a prefix (like shell tab-completion). Directories are
    suffixed with ["/"]. Used to drive live path suggestions. *)
val path_completions : string -> string list
