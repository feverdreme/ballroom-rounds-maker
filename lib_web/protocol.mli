open! Core
module Round = Rounds_model.Round

type workspace =
  { rounds_dir : string
  ; source_dir : string
  }
[@@deriving sexp]

type round_summary =
  { path : string
  ; name : string
  ; event_count : int
  }
[@@deriving sexp]

type initialize_request = workspace [@@deriving sexp]

type initialize_result =
  { rounds : round_summary list
  ; songs : string list
  }
[@@deriving sexp]

type load_request =
  { workspace : workspace
  ; path : string
  }
[@@deriving sexp]

type save_request =
  { workspace : workspace
  ; path : string option
  ; round : Round.t
  }
[@@deriving sexp]

type save_result = { path : string } [@@deriving sexp]

(* XCR aide for jeffrey: Just use Or_error.t instead of this type. *)
