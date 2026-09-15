open! Core

let rec walk_abs dir =
  match Sys_unix.readdir dir with
  | entries ->
    Array.to_list entries
    |> List.concat_map ~f:(fun entry ->
      if String.is_prefix entry ~prefix:"."
      then []
      else (
        let full = Filename.concat dir entry in
        match Sys_unix.is_directory full with
        | `Yes -> walk_abs full
        | `No | `Unknown -> [ full ]))
  | exception _ -> []
;;

let has_extension path ~extensions =
  match Filename.split_extension path with
  | _, None -> false
  | _, Some ext -> List.mem extensions (String.lowercase ("." ^ ext)) ~equal:String.equal
;;

(* Return [path] relative to [root], or unchanged when it is outside [root]. *)
let relative_to ~root path =
  let root = if String.is_suffix root ~suffix:"/" then root else root ^ "/" in
  match String.chop_prefix path ~prefix:root with
  | Some relative -> relative
  | None -> path
;;

let list_files_by_extension_abs ~root ~extensions =
  let%bind.Or_error is_directory =
    Or_error.try_with (fun () -> Sys_unix.is_directory_exn root)
  in
  if not is_directory
  then Or_error.errorf "%s is not a directory" root
  else
    Ok
      (walk_abs root
       |> List.filter ~f:(has_extension ~extensions)
       |> List.sort ~compare:String.compare)
;;

let list_files_by_extension ~root ~extensions =
  Or_error.map (list_files_by_extension_abs ~root ~extensions) ~f:(fun paths ->
    List.map paths ~f:(relative_to ~root))
;;

let path_completions buffer =
  let dir_part, prefix_part =
    match String.rsplit2 buffer ~on:'/' with
    | Some (directory, prefix) ->
      (if String.is_empty directory then "/" else directory), prefix
    | None -> ".", buffer
  in
  match Sys_unix.readdir dir_part with
  | entries ->
    Array.to_list entries
    |> List.filter ~f:(fun entry ->
      String.is_prefix entry ~prefix:prefix_part
      && not (String.is_prefix entry ~prefix:"."))
    |> List.map ~f:(fun entry ->
      let joined =
        if String.equal dir_part "."
        then entry
        else if String.equal dir_part "/"
        then "/" ^ entry
        else dir_part ^ "/" ^ entry
      in
      match Sys_unix.is_directory joined with
      | `Yes -> joined ^ "/"
      | `No | `Unknown -> joined)
    |> List.sort ~compare:String.compare
  | exception _ -> []
;;

let sanitize_filename string =
  let sanitized =
    String.to_list string
    |> List.map ~f:(fun character ->
      if Char.is_alphanum character
         || Char.equal character '_'
         || Char.equal character '-'
      then character
      else '_')
    |> String.of_char_list
  in
  if String.is_empty sanitized then "round" else sanitized
;;
