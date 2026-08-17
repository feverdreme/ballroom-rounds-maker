open! Core

module Song : sig
  type t =
    { filepath : Filename.t
    ; duration : int
    ; fade_in : int
    ; fade_out : int
    }
  [@@deriving sexp]

  val create
    :  filepath:string
    -> duration:int
    -> fade_in:int
    -> fade_out:int
    -> t Or_error.t
end

module Break : sig
  type t = { duration : int } [@@deriving sexp]
end

module Event : sig
  type t =
    | Song of
        { song : Song.t
        ; name : string option
        ; dance : string option
        }
    | Break of Break.t
  [@@deriving sexp]
end

type t =
  { events : Event.t list
  ; name : string
  }
[@@deriving sexp]

val save_to_file : t -> output_path:string -> unit

val read_from_file : filepath:string -> t