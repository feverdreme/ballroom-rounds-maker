open! Core

(** A Model Context Protocol server over stdio. Its tools manage round sexp files,
    download source songs with spotDL, and produce round MP3s, all confined to the
    directories given on the command line. *)
val command : Command.t
