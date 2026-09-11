open! Core

type summary =
  { path : string
  ; name : string
  ; event_count : int
  }
[@@deriving sexp]

val list : rounds_dir:Base_path.t -> summary list Or_error.t
val load : rounds_dir:Base_path.t -> path:string -> Rounds_model.Round.t Or_error.t

val save
  :  rounds_dir:Base_path.t
  -> path:string
  -> Rounds_model.Round.t
  -> unit Or_error.t

val path_for_new_round : Rounds_model.Round.t -> string
