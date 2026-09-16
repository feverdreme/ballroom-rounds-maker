open! Core
open! Async
module Protocol = Rounds_web_protocol.Protocol
module Round = Rounds_model.Round
module Server = Rounds_web_server.Server

let call endpoint body =
  let headers = Cohttp.Header.init_with "Content-Type" "application/sexp" in
  let request = Cohttp.Request.make ~meth:`POST ~headers (Uri.of_string endpoint) in
  let%bind response, response_body =
    Server.For_testing.callback
      ~app_js:""
      ~body:(Cohttp_async.Body.of_string body)
      ()
      request
  in
  let%map response_body = Cohttp_async.Body.to_string response_body in
  Cohttp.Response.status response, Sexp.of_string response_body
;;

let assert_application_error_is_readable () =
  let missing_source =
    Filename.concat
      Filename.temp_dir_name
      "ballroom-rounds-maker-source-that-does-not-exist"
  in
  let request =
    Protocol.{ rounds_dir = Filename.temp_dir_name; source_dir = missing_source }
  in
  let%map status, response =
    call "/api/initialize" (Protocol.sexp_of_initialize_request request |> Sexp.to_string)
  in
  assert (Cohttp.Code.code_of_status status = 200);
  match Or_error.t_of_sexp Protocol.initialize_result_of_sexp response with
  | Error error ->
    assert (String.is_substring (Error.to_string_hum error) ~substring:missing_source)
  | Ok _ -> failwith "Expected workspace initialization to fail"
;;

let assert_round_saves_and_loads () =
  let directory =
    Core_unix.mkdtemp
      (Filename.concat Filename.temp_dir_name "ballroom-rounds-maker-web-test-")
  in
  let saved_file = Filename.concat directory "Server_round_trip.sexp" in
  Monitor.protect
    ~finally:(fun () ->
      if Sys_unix.file_exists_exn saved_file then Core_unix.unlink saved_file;
      Core_unix.rmdir directory;
      return ())
    (fun () ->
      let workspace = Protocol.{ rounds_dir = directory; source_dir = directory } in
      let round =
        Round.{ events = [ Break { duration = 8 } ]; name = "Server round trip" }
      in
      let save_request = Protocol.{ workspace; path = None; round } in
      let%bind save_status, save_response =
        call "/api/save" (Protocol.sexp_of_save_request save_request |> Sexp.to_string)
      in
      assert (Cohttp.Code.code_of_status save_status = 200);
      let saved_path =
        match Or_error.t_of_sexp Protocol.save_result_of_sexp save_response with
        | Ok result -> result.path
        | Error error -> Error.raise error
      in
      let load_request = Protocol.{ workspace; path = saved_path } in
      let%map load_status, load_response =
        call "/api/load" (Protocol.sexp_of_load_request load_request |> Sexp.to_string)
      in
      assert (Cohttp.Code.code_of_status load_status = 200);
      match Or_error.t_of_sexp Round.t_of_sexp load_response with
      | Error error -> Error.raise error
      | Ok loaded -> assert (Sexp.equal (Round.sexp_of_t round) (Round.sexp_of_t loaded)))
;;

let assert_catalog_endpoints_rescan () =
  let directory =
    Core_unix.mkdtemp
      (Filename.concat Filename.temp_dir_name "ballroom-rounds-maker-catalog-test-")
  in
  let round_file = Filename.concat directory "external.sexp" in
  let song_file = Filename.concat directory "external.mp3" in
  Monitor.protect
    ~finally:(fun () ->
      if Sys_unix.file_exists_exn round_file then Core_unix.unlink round_file;
      if Sys_unix.file_exists_exn song_file then Core_unix.unlink song_file;
      Core_unix.rmdir directory;
      return ())
    (fun () ->
      let workspace = Protocol.{ rounds_dir = directory; source_dir = directory } in
      let list_rounds () =
        let%map status, response =
          call
            "/api/rounds"
            (Protocol.sexp_of_list_rounds_request workspace |> Sexp.to_string)
        in
        assert (Cohttp.Code.code_of_status status = 200);
        Or_error.t_of_sexp Protocol.list_rounds_result_of_sexp response |> Or_error.ok_exn
      in
      let list_songs () =
        let%map status, response =
          call
            "/api/songs"
            (Protocol.sexp_of_list_songs_request workspace |> Sexp.to_string)
        in
        assert (Cohttp.Code.code_of_status status = 200);
        Or_error.t_of_sexp Protocol.list_songs_result_of_sexp response |> Or_error.ok_exn
      in
      let%bind rounds_before = list_rounds ()
      and songs_before = list_songs () in
      assert (List.is_empty rounds_before);
      assert (List.is_empty songs_before);
      Round.save_to_file
        Round.{ events = [ Break { duration = 5 } ]; name = "External round" }
        ~output_path:round_file;
      Out_channel.write_all song_file ~data:"audio";
      let%bind rounds_after_add = list_rounds ()
      and songs_after_add = list_songs () in
      assert (
        List.equal
          (fun (left : Protocol.round_summary) (right : Protocol.round_summary) ->
            String.equal left.path right.path
            && String.equal left.name right.name
            && Int.equal left.event_count right.event_count)
          rounds_after_add
          [ { Protocol.path = "external.sexp"; name = "External round"; event_count = 1 }
          ]);
      assert (List.equal String.equal songs_after_add [ "external.mp3" ]);
      Core_unix.unlink round_file;
      Core_unix.unlink song_file;
      let%bind rounds_after_remove = list_rounds ()
      and songs_after_remove = list_songs () in
      assert (List.is_empty rounds_after_remove);
      assert (List.is_empty songs_after_remove);
      return ())
;;

let () =
  Thread_safe.block_on_async_exn (fun () ->
    let%bind () = assert_application_error_is_readable () in
    let%bind () = assert_round_saves_and_loads () in
    assert_catalog_endpoints_rescan ())
;;
