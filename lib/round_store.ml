open! Core
module Round = Rounds_model.Round

type summary =
  { path : string
  ; name : string
  ; event_count : int
  }
[@@deriving sexp]

let validate_relative_path path =
  if String.is_empty path || not (Filename.is_relative path)
  then Or_error.error_string "Round path must be a non-empty relative path"
  else (
    let segments = String.split path ~on:'/' in
    if List.exists segments ~f:(fun segment ->
         String.is_empty segment || String.equal segment "." || String.equal segment "..")
    then Or_error.error_string "Round path contains an invalid segment"
    else Ok path)
;;

let resolve ~rounds_dir path =
  let%map.Or_error path = validate_relative_path path in
  Filename.concat (Base_path.get_path rounds_dir) path
;;

let list ~rounds_dir =
  let root = Base_path.get_path rounds_dir in
  let%bind.Or_error paths =
    File_browser.list_files_by_extension ~root ~extensions:[ ".sexp" ]
  in
  List.map paths ~f:(fun path ->
    let%map.Or_error round =
      Or_error.try_with (fun () ->
        let absolute = Filename.concat root path in
        Round.read_from_file ~filepath:absolute)
    in
    { path; name = round.name; event_count = List.length round.events })
  |> Or_error.combine_errors
;;

let load ~rounds_dir ~path =
  let%bind.Or_error absolute = resolve ~rounds_dir path in
  Or_error.try_with (fun () -> Round.read_from_file ~filepath:absolute)
;;

let save ~rounds_dir ~path round =
  let%bind.Or_error () = Base_path.instantiate rounds_dir in
  let%bind.Or_error absolute = resolve ~rounds_dir path in
  Or_error.try_with (fun () -> Round.save_to_file round ~output_path:absolute)
;;

let path_for_new_round round = File_browser.sanitize_filename round.Round.name ^ ".sexp"
