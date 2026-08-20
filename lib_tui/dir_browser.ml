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

let relative_to ~root path =
  let root = if String.is_suffix root ~suffix:"/" then root else root ^ "/" in
  match String.chop_prefix path ~prefix:root with
  | Some rel -> rel
  | None -> path
;;

let list_files_by_extension_abs ~root ~extensions =
  Or_error.try_with (fun () ->
    walk_abs root |> List.filter ~f:(has_extension ~extensions) |> List.sort ~compare:String.compare)
;;

let list_files_by_extension ~root ~extensions =
  Or_error.map (list_files_by_extension_abs ~root ~extensions) ~f:(fun paths ->
    List.map paths ~f:(relative_to ~root))
;;

let path_completions buffer =
  let dir_part, prefix_part =
    match String.rsplit2 buffer ~on:'/' with
    | Some (d, p) -> (if String.is_empty d then "/" else d), p
    | None -> ".", buffer
  in
  match Sys_unix.readdir dir_part with
  | entries ->
    Array.to_list entries
    |> List.filter ~f:(fun e ->
      String.is_prefix e ~prefix:prefix_part && not (String.is_prefix e ~prefix:"."))
    |> List.map ~f:(fun e ->
      let joined =
        if String.equal dir_part "."
        then e
        else if String.equal dir_part "/"
        then "/" ^ e
        else dir_part ^ "/" ^ e
      in
      match Sys_unix.is_directory joined with
      | `Yes -> joined ^ "/"
      | `No | `Unknown -> joined)
    |> List.sort ~compare:String.compare
  | exception _ -> []
;;

let sanitize_filename s =
  let sanitized =
    String.to_list s
    |> List.map ~f:(fun c ->
      if Char.is_alphanum c || Char.equal c '_' || Char.equal c '-' then c else '_')
    |> String.of_char_list
  in
  if String.is_empty sanitized then "round" else sanitized
;;
