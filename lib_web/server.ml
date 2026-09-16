open! Core
open! Async
module Http_server = Cohttp_async.Server
module Protocol = Rounds_web_protocol.Protocol
module Round = Rounds_lib.Round

let sexp_headers =
  Cohttp.Header.init_with "Content-Type" "application/sexp; charset=utf-8"
;;

let text_headers content_type =
  Cohttp.Header.init_with "Content-Type" content_type
  |> fun headers -> Cohttp.Header.add headers "Cache-Control" "no-store"
;;

let respond_string ?(status = `OK) ~content_type body =
  Http_server.respond_string ~status ~headers:(text_headers content_type) body
;;

let respond_sexp ?(status = `OK) sexp =
  Http_server.respond_string ~status ~headers:sexp_headers (Sexp.to_string_hum sexp)
;;

let respond_error sexp_of error =
  (* Application errors remain successful HTTP exchanges so the Bonsai client can
     deserialize and display the useful error text. [Async_js.Http] intentionally turns
     non-2xx responses into a generic transport error and does not expose their body. *)
  respond_sexp (Or_error.sexp_of_t sexp_of (Error error))
;;

let rounds_path (workspace : Protocol.workspace) =
  Rounds_lib.Base_path.create ~base_dir:(String.strip workspace.rounds_dir)
;;

let source_path (workspace : Protocol.workspace) =
  Rounds_lib.Base_path.create ~base_dir:(String.strip workspace.source_dir)
;;

let list_rounds (request : Protocol.list_rounds_request) =
  let%bind.Or_error rounds_dir = rounds_path request in
  let%map.Or_error rounds =
    if Sys_unix.file_exists_exn (Rounds_lib.Base_path.get_path rounds_dir)
    then Rounds_lib.Round_store.list ~rounds_dir
    else Ok []
  in
  List.map rounds ~f:(fun (summary : Rounds_lib.Round_store.summary) ->
    Protocol.
      { path = summary.path; name = summary.name; event_count = summary.event_count })
;;

let list_songs (request : Protocol.list_songs_request) =
  let%bind.Or_error source_dir = source_path request in
  Rounds_lib.File_browser.list_files_by_extension
    ~root:(Rounds_lib.Base_path.get_path source_dir)
    ~extensions:[ ".mp3"; ".wav"; ".m4a" ]
;;

let initialize (request : Protocol.initialize_request) =
  let%bind.Or_error rounds = list_rounds request in
  let%map.Or_error songs = list_songs request in
  Protocol.{ rounds; songs }
;;

let load_round (request : Protocol.load_request) =
  let%bind.Or_error rounds_dir = rounds_path request.workspace in
  Rounds_lib.Round_store.load ~rounds_dir ~path:request.path
;;

let validate_nonnegative label value =
  if value < 0 then Or_error.errorf "%s cannot be negative" label else Ok ()
;;

let validate_round (round : Round.t) =
  if String.is_empty (String.strip round.name)
  then Or_error.error_string "Round name cannot be empty"
  else
    List.map round.events ~f:(function
      | Round.Event.Break break -> validate_nonnegative "Break duration" break.duration
      | Song { song_data = song; _ } ->
        let%bind.Or_error () = validate_nonnegative "Song duration" song.duration in
        let%bind.Or_error () = validate_nonnegative "Fade in" song.fade_in in
        let%bind.Or_error () = validate_nonnegative "Fade out" song.fade_out in
        Round.Song.create
          ~filepath:song.filepath
          ~duration:song.duration
          ~fade_in:song.fade_in
          ~fade_out:song.fade_out
        |> Or_error.ignore_m)
    |> Or_error.combine_errors_unit
;;

let save_round (request : Protocol.save_request) =
  let%bind.Or_error rounds_dir = rounds_path request.workspace in
  let%bind.Or_error () = validate_round request.round in
  (* CR aide for jeffrey: A new round silently overwrites an existing file when its
     sanitized name collides. This is especially easy to hit because every new editor
     starts as [Untitled round]. Please either allocate a unique path or reject the save
     when the derived path already exists; otherwise creating a second round can destroy
     the first one. *)
  let path =
    Option.value
      request.path
      ~default:(Rounds_lib.Round_store.path_for_new_round request.round)
  in
  let%map.Or_error () = Rounds_lib.Round_store.save ~rounds_dir ~path request.round in
  Protocol.{ path }
;;

let parse_body body of_sexp =
  let%map body = Cohttp_async.Body.to_string body in
  Or_error.try_with (fun () -> Sexp.of_string body |> of_sexp)
;;

let handle_post ~body ~request ~of_sexp ~sexp_of_result ~handle =
  let content_type = Cohttp.Header.get (Cohttp.Request.headers request) "content-type" in
  match content_type with
  | Some value when String.is_prefix (String.lowercase value) ~prefix:"application/sexp"
    ->
    let%bind parsed = parse_body body of_sexp in
    (match Result.bind parsed ~f:handle with
     | Ok result -> respond_sexp (Or_error.sexp_of_t sexp_of_result (Ok result))
     | Error error -> respond_error sexp_of_result error)
  | _ ->
    respond_string
      ~status:`Unsupported_media_type
      ~content_type:"text/plain"
      "Expected application/sexp"
;;

let origin_is_allowed request =
  let headers = Cohttp.Request.headers request in
  match Cohttp.Header.get headers "origin" with
  | None -> true
  | Some origin ->
    (match Cohttp.Header.get headers "host" with
     | None -> false
     | Some host -> String.equal origin ("http://" ^ host))
;;

let callback ~app_js ~body _socket request =
  let path = Uri.path (Cohttp.Request.uri request) in
  match Cohttp.Request.meth request, path with
  | `GET, "/" ->
    respond_string ~content_type:"text/html; charset=utf-8" Web_assets.index_html
  | `GET, "/app.css" ->
    respond_string ~content_type:"text/css; charset=utf-8" Web_assets.stylesheet
  | `GET, "/app.js" ->
    Http_server.respond_with_file
      ~headers:(text_headers "text/javascript; charset=utf-8")
      app_js
  | `GET, "/health" -> respond_string ~content_type:"text/plain; charset=utf-8" "ok\n"
  | `POST, _ when not (origin_is_allowed request) ->
    respond_string
      ~status:`Forbidden
      ~content_type:"text/plain; charset=utf-8"
      "Cross-origin request rejected"
  | `POST, "/api/initialize" ->
    handle_post
      ~body
      ~request
      ~of_sexp:Protocol.initialize_request_of_sexp
      ~sexp_of_result:Protocol.sexp_of_initialize_result
      ~handle:initialize
  | `POST, "/api/rounds" ->
    handle_post
      ~body
      ~request
      ~of_sexp:Protocol.list_rounds_request_of_sexp
      ~sexp_of_result:Protocol.sexp_of_list_rounds_result
      ~handle:list_rounds
  | `POST, "/api/songs" ->
    handle_post
      ~body
      ~request
      ~of_sexp:Protocol.list_songs_request_of_sexp
      ~sexp_of_result:Protocol.sexp_of_list_songs_result
      ~handle:list_songs
  | `POST, "/api/load" ->
    handle_post
      ~body
      ~request
      ~of_sexp:Protocol.load_request_of_sexp
      ~sexp_of_result:Round.sexp_of_t
      ~handle:load_round
  | `POST, "/api/save" ->
    handle_post
      ~body
      ~request
      ~of_sexp:Protocol.save_request_of_sexp
      ~sexp_of_result:Protocol.sexp_of_save_result
      ~handle:save_round
  | _ ->
    respond_string
      ~status:`Not_found
      ~content_type:"text/plain; charset=utf-8"
      "Not found\n"
;;

module For_testing = struct
  let callback = callback
end

let default_assets_dir () =
  let executable =
    if Filename.is_relative Sys_unix.executable_name
    then Filename.concat (Sys_unix.getcwd ()) Sys_unix.executable_name
    else Sys_unix.executable_name
  in
  Filename.concat (Filename.dirname executable) "../lib_web"
;;

let command =
  Command.async
    ~summary:"Run the local Ballroom Rounds Maker web app"
    (let%map_open.Command port =
       flag
         "-port"
         (optional_with_default 8080 int)
         ~doc:"PORT local port (default: 8080)"
     and assets_dir =
       flag
         "-assets-dir"
         (optional string)
         ~doc:"DIR directory containing client.bc.js (normally inferred)"
     in
     fun () ->
       let assets_dir = Option.value assets_dir ~default:(default_assets_dir ()) in
       let app_js = Filename.concat assets_dir "client.bc.js" in
       if not (Sys_unix.file_exists_exn app_js)
       then raise_s [%message "Web client asset not found" (app_js : string)];
       let where_to_listen =
         Tcp.Where_to_listen.bind_to
           Tcp.Bind_to_address.Localhost
           (Tcp.Bind_to_port.On_port port)
       in
       let%bind _server =
         Http_server.create
           ~on_handler_error:
             (`Call
               (fun _ error -> eprintf "Web request failed: %s\n" (Exn.to_string error)))
           where_to_listen
           (callback ~app_js)
       in
       printf "Ballroom Rounds Maker is running at http://127.0.0.1:%d\n%!" port;
       Deferred.never ())
;;
