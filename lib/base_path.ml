open! Core

type t = string

let create ~base_dir =
  if String.is_empty base_dir
  then
    Or_error.error_s
      [%message "Base_path.create: base_dir must not be empty" (base_dir : string)]
  else if String.contains base_dir '\000'
  then
    Or_error.error_s
      [%message
        "Base_path.create: base_dir must not contain a NUL byte" (base_dir : string)]
  else Ok base_dir
;;

let get_path t = t
let derive_path t path = Filename.concat t path

let instantiate t =
  Core_unix.mkdir_p ~perm:0o755 (get_path t);
  if Sys_unix.is_directory_exn (get_path t)
  then Ok ()
  else
    Or_error.error_s
      [%message "Could not instantiate directory." ~dir:(get_path t : string)]
;;
