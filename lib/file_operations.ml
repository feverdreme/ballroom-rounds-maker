open! Core
open Core_unix

(** Recursively create directories along [path], like [mkdir -p]. *)
let rec mkdir_p path =
  if Sys_unix.file_exists_exn path then ()
  else begin
    let parent = Filename.dirname path in
    if String.(parent <> path) then mkdir_p parent;
    (try mkdir ~perm:0o755 path
     with Unix_error (EEXIST, _, _) -> ())
  end

(** Copy a file from [src] to [dst] using the system [cp] command. *)
let copy_file ~src ~dst =
  let cmd = Printf.sprintf "cp %s %s" (Filename.quote src) (Filename.quote dst) in
  let exit_code = Sys_unix.command cmd in
  if exit_code <> 0 then
    Printf.ksprintf failwith "copy_file: cp failed with exit code %d" exit_code

(** Normalize a filename by stripping apostrophes, spaces, and replacing hyphens with underscores. *)
let normalize_filename (s : string) : string =
  let open Core in 
  s
  |> String.substr_replace_all ~pattern:"'" ~with_:""
  |> String.substr_replace_all ~pattern:" " ~with_:""
  |> String.substr_replace_all ~pattern:"-" ~with_:"_"

(** Return true if [filename] exists within [directory]. *)
let file_exists (directory : string) (filename : string) : bool =
  let path = Filename.concat directory filename in
  Sys_unix.file_exists_exn path

(** Return true if every event name in [events] corresponds to an existing file in [directory]. *)
let check_event_files_exist (directory : string) (events : string list) : bool =
  List.for_all events ~f:(file_exists directory)