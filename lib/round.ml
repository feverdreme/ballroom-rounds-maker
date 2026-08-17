open! Core

module Song = struct
  type t =
    { filepath : string
    ; duration : int
    ; fade_in : int
    ; fade_out : int
    }
  [@@deriving sexp]

  let create ~filepath ~duration ~fade_in ~fade_out =
    if fade_in + fade_out > duration
    then
      Or_error.error_s
        [%message
          "Fade in and fade out cannot be longer than the duration itself"
            (fade_in : int)
            (fade_out : int)
            (duration : int)]
    else { filepath; duration; fade_in; fade_out } |> Or_error.return
  ;;
end

module Break = struct
  type t = { duration : int } [@@deriving sexp]
end

module Event = struct
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

let save_to_file t ~output_path = Sexp.save_hum output_path (sexp_of_t t)

let read_from_file ~filepath = In_channel.read_all filepath |> Sexp.of_string |> t_of_sexp