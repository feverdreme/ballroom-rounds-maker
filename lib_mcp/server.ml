open! Core
module Base_path = Rounds_lib.Base_path
module Round = Rounds_lib.Round
module Round_store = Rounds_lib.Round_store

let protocol_version = "2025-06-18"
let audio_extensions = [ ".mp3"; ".wav"; ".m4a" ]

type t =
  { rounds_dir : Base_path.t
  ; source_dir : Base_path.t
  ; artifact_dir : Base_path.t
  ; output_dir : Base_path.t
  ; ffmpeg_path : string
  ; spotdl_path : string
  ; spotdl_config : string
  ; use_official_spotify_api : bool
  }

(* Tool arguments *)

let string_arg arguments name =
  match Yojson.Safe.Util.member name arguments with
  | `String value -> Ok value
  | _ -> Or_error.error_s [%message "Expected a string argument" (name : string)]
;;

let optional_string_arg arguments name =
  match Yojson.Safe.Util.member name arguments with
  | `Null -> Ok None
  | `String value -> Ok (Some value)
  | _ -> Or_error.error_s [%message "Expected a string argument" (name : string)]
;;

let string_list_arg arguments name =
  let error = Or_error.error_s [%message "Expected a list of strings" (name : string)] in
  match Yojson.Safe.Util.member name arguments with
  | `List values ->
    List.map values ~f:(function
      | `String value -> Ok value
      | _ -> error)
    |> Or_error.combine_errors
  | _ -> error
;;

(* Tool implementations. Each returns the text shown to the agent; rounds and summaries
   are rendered as sexps so the agent sees the same format as the files. *)

let render sexp = Sexp.to_string_hum sexp

let list_songs t =
  if Sys_unix.file_exists_exn (Base_path.get_path t.source_dir)
  then
    Rounds_lib.File_browser.list_files_by_extension
      ~root:(Base_path.get_path t.source_dir)
      ~extensions:audio_extensions
  else Ok []
;;

let list_rounds t =
  if Sys_unix.file_exists_exn (Base_path.get_path t.rounds_dir)
  then Round_store.list ~rounds_dir:t.rounds_dir
  else Ok []
;;

(* Catch errors that would otherwise only surface halfway through an ffmpeg run. *)
let validate_round t (round : Round.t) =
  List.mapi round.events ~f:(fun index event ->
    let check =
      match event with
      | Round.Event.Break { duration } ->
        if duration > 0
        then Ok ()
        else
          Or_error.error_s [%message "Break duration must be positive" (duration : int)]
      | Song { song_data = { filepath; duration; fade_in; fade_out }; _ } ->
        let%bind.Or_error (_ : Round.Song.t) =
          Round.Song.create ~filepath ~duration ~fade_in ~fade_out
        in
        if Sys_unix.file_exists_exn (Base_path.derive_path t.source_dir filepath)
        then Ok ()
        else
          Or_error.error_s
            [%message "Song file not found in the source directory" (filepath : string)]
    in
    Or_error.tag_s check ~tag:[%message "Invalid event" (index : int)])
  |> Or_error.combine_errors_unit
;;

let parse_round text =
  Or_error.try_with (fun () -> Sexp.of_string text |> Round.t_of_sexp)
  |> Or_error.tag ~tag:"Round is not a valid Round.t sexp"
;;

let save_round t arguments =
  let%bind.Or_error text = string_arg arguments "round" in
  let%bind.Or_error path = optional_string_arg arguments "path" in
  let%bind.Or_error round = parse_round text in
  let%bind.Or_error () = validate_round t round in
  let%bind.Or_error path =
    match path with
    | Some path -> Ok path
    | None ->
      (* Without an explicit path, refuse to clobber a round with a colliding name. *)
      let path = Round_store.path_for_new_round round in
      if Sys_unix.file_exists_exn (Base_path.derive_path t.rounds_dir path)
      then
        Or_error.error_s
          [%message "A round already exists at this path; pass it to overwrite" path]
      else Ok path
  in
  let%map.Or_error () = Round_store.save ~rounds_dir:t.rounds_dir ~path round in
  [%string "Saved %{path}"]
;;

let download_songs t arguments =
  let%bind.Or_error urls = string_list_arg arguments "urls" in
  let%bind.Or_error before = list_songs t in
  let%bind.Or_error () =
    Rounds_lib.Spotdl.download
      ~spotdl_path:t.spotdl_path
      ~config_path:t.spotdl_config
      ~use_official_api:t.use_official_spotify_api
      ~queries:urls
      ~source_path:t.source_dir
      ()
  in
  let%map.Or_error after = list_songs t in
  let added =
    List.filter after ~f:(fun song -> not (List.mem before song ~equal:String.equal))
  in
  render [%sexp { added : string list }]
;;

let produce_round t arguments =
  let%bind.Or_error path = string_arg arguments "path" in
  let%bind.Or_error round = Round_store.load ~rounds_dir:t.rounds_dir ~path in
  let%bind.Or_error () = validate_round t round in
  let%bind.Or_error () = Base_path.instantiate t.output_dir in
  (* [path] was validated as relative by [Round_store.load]; mirror it in the output
     directory. *)
  let output_path =
    Base_path.derive_path t.output_dir (String.chop_suffix_if_exists path ~suffix:".sexp")
    ^ ".mp3"
  in
  let%bind.Or_error () =
    Or_error.try_with (fun () ->
      Core_unix.mkdir_p (Filename.dirname output_path) |> Fn.ignore)
  in
  let%map.Or_error () =
    Rounds_lib.Converter.convert
      ~ffmpeg_path:t.ffmpeg_path
      ~round
      ~source_path:t.source_dir
      ~artifact_path:t.artifact_dir
      ~output_path
      ()
  in
  [%string "Produced %{output_path}"]
;;

type tool =
  { name : string
  ; description : string
  ; properties : (string * Yojson.Safe.t) list
  ; required : string list
  ; read_only : bool
  ; run : t -> Yojson.Safe.t -> string Or_error.t
  }

let string_schema description =
  `Assoc [ "type", `String "string"; "description", `String description ]
;;

let round_path_schema =
  string_schema "Round sexp path, relative to the rounds directory (from list_rounds)"
;;

let tools =
  [ { name = "list_rounds"
    ; description = "List round sexp files with their names and event counts."
    ; properties = []
    ; required = []
    ; read_only = true
    ; run =
        (fun t _ ->
          let%map.Or_error rounds = list_rounds t in
          render [%sexp (rounds : Round_store.summary list)])
    }
  ; { name = "list_songs"
    ; description =
        "List audio files in the source directory. Song filepaths in a round must be one \
         of these."
    ; properties = []
    ; required = []
    ; read_only = true
    ; run =
        (fun t _ ->
          let%map.Or_error songs = list_songs t in
          render [%sexp (songs : string list)])
    }
  ; { name = "get_round"
    ; description = "Read a round as a Round.t sexp."
    ; properties = [ "path", round_path_schema ]
    ; required = [ "path" ]
    ; read_only = true
    ; run =
        (fun t arguments ->
          let%bind.Or_error path = string_arg arguments "path" in
          let%map.Or_error round = Round_store.load ~rounds_dir:t.rounds_dir ~path in
          render (Round.sexp_of_t round))
    }
  ; { name = "save_round"
    ; description =
        "Validate and save a Round.t sexp. Events are (Song (song_data ((filepath F) \
         (duration D) (fade_in I) (fade_out O))) (name ()) (dance ())) or (Break \
         ((duration D))), with times in seconds. Song filepaths must exist in the source \
         directory and fade_in + fade_out must not exceed duration. Without a path, \
         saves a new round named after the round and refuses to overwrite."
    ; properties =
        [ "round", string_schema "The round as a Round.t sexp"
        ; ( "path"
          , string_schema
              "Optional relative path to write; an existing round there is overwritten" )
        ]
    ; required = [ "round" ]
    ; read_only = false
    ; run = save_round
    }
  ; { name = "delete_round"
    ; description = "Delete a round sexp file."
    ; properties = [ "path", round_path_schema ]
    ; required = [ "path" ]
    ; read_only = false
    ; run =
        (fun t arguments ->
          let%bind.Or_error path = string_arg arguments "path" in
          let%map.Or_error () = Round_store.delete ~rounds_dir:t.rounds_dir ~path in
          [%string "Deleted %{path}"])
    }
  ; { name = "download_songs"
    ; description =
        "Download Spotify tracks, albums, playlists, or artists as MP3s into the source \
         directory with spotDL. Returns the newly added song paths."
    ; properties =
        [ ( "urls"
          , `Assoc
              [ "type", `String "array"
              ; "items", `Assoc [ "type", `String "string" ]
              ; "description", `String "Spotify URLs"
              ] )
        ]
    ; required = [ "urls" ]
    ; read_only = false
    ; run = download_songs
    }
  ; { name = "produce_round"
    ; description =
        "Render a saved round into a single MP3 in the output directory, at the round's \
         relative path with an .mp3 extension."
    ; properties = [ "path", round_path_schema ]
    ; required = [ "path" ]
    ; read_only = false
    ; run = produce_round
    }
  ]
;;

let tool_to_json tool =
  `Assoc
    [ "name", `String tool.name
    ; "description", `String tool.description
    ; ( "inputSchema"
      , `Assoc
          [ "type", `String "object"
          ; "properties", `Assoc tool.properties
          ; "required", `List (List.map tool.required ~f:(fun name -> `String name))
          ] )
    ; "annotations", `Assoc [ "readOnlyHint", `Bool tool.read_only ]
    ]
;;

(* JSON-RPC *)

let call_tool t params =
  let open Yojson.Safe.Util in
  let name = member "name" params in
  let arguments =
    match member "arguments" params with
    | `Null -> `Assoc []
    | arguments -> arguments
  in
  let result =
    match name with
    | `String name ->
      (match List.find tools ~f:(fun tool -> String.equal tool.name name) with
       | Some tool -> Or_error.try_with_join (fun () -> tool.run t arguments)
       | None -> Or_error.error_s [%message "Unknown tool" name])
    | _ -> Or_error.error_string "Tool name must be a string"
  in
  let text, is_error =
    match result with
    | Ok text -> text, false
    | Error error -> Error.to_string_hum error, true
  in
  `Assoc
    [ "content", `List [ `Assoc [ "type", `String "text"; "text", `String text ] ]
    ; "isError", `Bool is_error
    ]
;;

let handle_request t ~meth ~params =
  match meth with
  | "initialize" ->
    Ok
      (`Assoc
        [ "protocolVersion", `String protocol_version
        ; "capabilities", `Assoc [ "tools", `Assoc [] ]
        ; "serverInfo", `Assoc [ "name", `String "rounds"; "version", `String "0.1.0" ]
        ])
  | "ping" -> Ok (`Assoc [])
  | "tools/list" -> Ok (`Assoc [ "tools", `List (List.map tools ~f:tool_to_json) ])
  | "tools/call" -> Ok (call_tool t params)
  | _ -> Error (-32601, [%string "Method not found: %{meth}"])
;;

let error_response ~id ~code ~message =
  `Assoc
    [ "jsonrpc", `String "2.0"
    ; "id", id
    ; "error", `Assoc [ "code", `Int code; "message", `String message ]
    ]
;;

(* Returns [None] for notifications, which get no response. *)
let handle_message t message =
  let open Yojson.Safe.Util in
  match member "id" message, member "method" message with
  | `Null, _ -> None
  | id, `String meth ->
    (match handle_request t ~meth ~params:(member "params" message) with
     | Ok result -> Some (`Assoc [ "jsonrpc", `String "2.0"; "id", id; "result", result ])
     | Error (code, message) -> Some (error_response ~id ~code ~message))
  | id, _ -> Some (error_response ~id ~code:(-32600) ~message:"Invalid request")
;;

(* MCP owns stdin and stdout, but ffmpeg, spotDL, and the library's progress printing all
   inherit or write to them. Keep private copies for the protocol, then point fd 1 at
   stderr and fd 0 at /dev/null so nothing else can corrupt the message stream. *)
let take_stdio () =
  let input = Core_unix.dup ~close_on_exec:true Core_unix.stdin in
  let output = Core_unix.dup ~close_on_exec:true Core_unix.stdout in
  let dev_null = Core_unix.openfile "/dev/null" ~mode:[ O_RDONLY ] in
  Core_unix.dup2 ~src:dev_null ~dst:Core_unix.stdin ();
  Core_unix.close dev_null;
  Core_unix.dup2 ~src:Core_unix.stderr ~dst:Core_unix.stdout ();
  Core_unix.in_channel_of_descr input, Core_unix.out_channel_of_descr output
;;

let serve t =
  let input, output = take_stdio () in
  let send json =
    Out_channel.output_string output (Yojson.Safe.to_string json);
    Out_channel.newline output;
    Out_channel.flush output
  in
  let rec loop () =
    match In_channel.input_line input with
    | None -> ()
    | Some line when String.is_empty (String.strip line) -> loop ()
    | Some line ->
      (match Yojson.Safe.from_string line with
       | message -> Option.iter (handle_message t message) ~f:send
       | exception Yojson.Json_error message ->
         send (error_response ~id:`Null ~code:(-32700) ~message));
      Out_channel.flush stdout;
      loop ()
  in
  loop ()
;;

let default_spotdl_config () =
  Filename.concat (Sys.getenv_exn "HOME") ".spotdl/config.json"
;;

let command =
  Command.basic_or_error
    ~summary:"Serve round management, song downloads, and production over MCP stdio"
    (let%map_open.Command rounds_dir =
       flag
         "-rounds-path"
         (required Filename_unix.arg_type)
         ~doc:"DIR directory of round sexp files"
     and source_dir =
       flag
         "-source-path"
         (required Filename_unix.arg_type)
         ~doc:"DIR directory of source audio; downloads land here"
     and artifact_dir =
       flag
         "-artifact-path"
         (required Filename_unix.arg_type)
         ~doc:"DIR directory for intermediate artifacts (trimmed songs, breaks)"
     and output_dir =
       flag
         "-output-path"
         (required Filename_unix.arg_type)
         ~doc:"DIR directory for produced round MP3s"
     and ffmpeg_path =
       flag
         "-ffmpeg-path"
         (optional_with_default "ffmpeg" string)
         ~doc:"PATH path to the ffmpeg binary (default: ffmpeg)"
     and spotdl_path =
       flag
         "-spotdl-path"
         (optional_with_default "spotdl" string)
         ~doc:"PATH path to the spotdl binary (default: spotdl)"
     and spotdl_config =
       flag
         "-spotdl-config"
         (optional_with_default (default_spotdl_config ()) Filename_unix.arg_type)
         ~doc:"PATH spotDL configuration file to load (default: ~/.spotdl/config.json)"
     and use_official_spotify_api =
       flag
         "-use-official-spotify-api"
         no_arg
         ~doc:" use Spotify's official Web API client"
     in
     fun () ->
       let%bind.Or_error rounds_dir = Base_path.create ~base_dir:rounds_dir in
       let%bind.Or_error source_dir = Base_path.create ~base_dir:source_dir in
       let%bind.Or_error artifact_dir = Base_path.create ~base_dir:artifact_dir in
       let%map.Or_error output_dir = Base_path.create ~base_dir:output_dir in
       serve
         { rounds_dir
         ; source_dir
         ; artifact_dir
         ; output_dir
         ; ffmpeg_path
         ; spotdl_path
         ; spotdl_config
         ; use_official_spotify_api
         })
;;
