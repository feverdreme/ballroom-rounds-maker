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

  let to_string t =
    (* let basename = Filename.basename t.filepath in *)
    [%string
      "%{t.filepath}_fadein_%{t.fade_in#Int}_duration_%{t.duration#Int}_fadeout_%{t.fade_out#Int}"]
  ;;
end

module Break = struct
  type t = { duration : int } [@@deriving sexp]

  let to_string t = [%string "break_%{t.duration#Int}"]
end

module Event = struct
  type t =
    | Song of
        { song_data : Song.t
        ; name : string option
        ; dance : string option
        }
    | Break of Break.t
  [@@deriving sexp]

  let to_string = function
    | Song s -> Song.to_string s.song_data
    | Break b -> Break.to_string b
  ;;
end

type t =
  { events : Event.t list
  ; name : string
  }
[@@deriving sexp]

let save_to_file t ~output_path = Sexp.save_hum output_path (sexp_of_t t)
let read_from_file ~filepath = In_channel.read_all filepath |> Sexp.of_string |> t_of_sexp
