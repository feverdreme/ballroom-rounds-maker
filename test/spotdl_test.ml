open! Core
open Async_log_kernel.Ppx_log_syntax

let log_info message =
  [%log.info "spotdl_test" (message : string)];
  Out_channel.flush stdout;
  Out_channel.flush stderr
;;

let run_test name test =
  log_info [%string "START %{name}"];
  match test () with
  | () -> log_info [%string "PASS  %{name}"]
  | exception exn ->
    log_info [%string "FAIL  %{name}: %{Exn.to_string exn}"];
    raise exn
;;

let source_path_exn path = Rounds_lib.Base_path.create ~base_dir:path |> Or_error.ok_exn

let verify_nonempty_mp3 ~source_dir filename =
  let mp3_path = Filename.concat source_dir filename in
  let byte_count = (Core_unix.stat mp3_path).st_size in
  let byte_count_string = Int64.to_string byte_count in
  log_info [%string "Verified %{filename} is %{byte_count_string} bytes"];
  assert (Int64.(byte_count > 0L))
;;

let test_real_spotdl_downloads_mp3 () =
  let root = Filename_unix.temp_dir "rounds-spotdl-" "" in
  let source_dir = Filename.concat root "source" in
  log_info [%string "Downloading spotDL sample track into %{source_dir}"];
  Exn.protect
    ~f:(fun () ->
      Rounds_lib.Spotdl.download
        ~queries:[ "https://open.spotify.com/track/0VjIjW4GlUZAMYd2vXMi3b" ]
        ~source_path:(source_path_exn source_dir)
        ()
      |> Or_error.ok_exn;
      assert (Sys_unix.is_directory_exn source_dir);
      let downloaded_mp3s =
        Sys_unix.ls_dir source_dir |> List.filter ~f:(String.is_suffix ~suffix:".mp3")
      in
      let downloaded_names = String.concat ~sep:", " downloaded_mp3s in
      log_info [%string "Downloaded MP3 files: %{downloaded_names}"];
      assert (not (List.is_empty downloaded_mp3s));
      List.iter downloaded_mp3s ~f:(verify_nonempty_mp3 ~source_dir))
    ~finally:(fun () ->
      log_info [%string "Cleaning up %{root}"];
      if Sys_unix.file_exists_exn source_dir
      then (
        Sys_unix.ls_dir source_dir
        |> List.iter ~f:(fun filename ->
          Core_unix.unlink (Filename.concat source_dir filename));
        Core_unix.rmdir source_dir);
      Core_unix.rmdir root)
;;

let test_nonzero_exit_is_an_error () =
  let source_dir = Filename_unix.temp_dir "rounds-spotdl-" "" in
  Exn.protect
    ~f:(fun () ->
      let result =
        Rounds_lib.Spotdl.download
          ~spotdl_path:"/usr/bin/false"
          ~queries:[ "https://open.spotify.com/track/example" ]
          ~source_path:(source_path_exn source_dir)
          ()
      in
      assert (Or_error.is_error result))
    ~finally:(fun () -> Core_unix.rmdir source_dir)
;;

let test_empty_query_list_is_an_error () =
  let result =
    Rounds_lib.Spotdl.download
      ~spotdl_path:"/usr/bin/true"
      ~queries:[]
      ~source_path:(source_path_exn ".")
      ()
  in
  assert (Or_error.is_error result)
;;

let () =
  run_test "real spotDL download produces an MP3" test_real_spotdl_downloads_mp3;
  run_test "nonzero spotDL exit is an error" test_nonzero_exit_is_an_error;
  run_test "empty query list is an error" test_empty_query_list_is_an_error;
  log_info "All tests passed"
;;
