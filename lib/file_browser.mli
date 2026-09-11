open! Core

val list_files_by_extension
  :  root:string
  -> extensions:string list
  -> string list Or_error.t

val list_files_by_extension_abs
  :  root:string
  -> extensions:string list
  -> string list Or_error.t

val sanitize_filename : string -> string
val path_completions : string -> string list
