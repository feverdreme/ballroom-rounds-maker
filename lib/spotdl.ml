open! Core

let output_template = "{artists} - {title}.{output-ext}"

let resolve_executable_path path =
  if Filename.is_relative path && String.contains path '/'
  then Filename.concat (Core_unix.getcwd ()) path
  else path
;;

let spotify_credentials_args ~client_id ~client_secret =
  match client_id, client_secret with
  | None, None -> Ok []
  | Some client_id, Some client_secret ->
    Ok [ "--client-id"; client_id; "--client-secret"; client_secret ]
  | Some _, None ->
    Or_error.error_string "A Spotify client secret is required with a client ID"
  | None, Some _ ->
    Or_error.error_string "A Spotify client ID is required with a client secret"
;;

let download
  ?(spotdl_path = "spotdl")
  ?(use_config = false)
  ?client_id
  ?client_secret
  ?(use_official_api = false)
  ~queries
  ~source_path
  ()
  =
  if List.is_empty queries
  then Or_error.error_string "At least one Spotify URL is required"
  else (
    let%bind.Or_error credential_args =
      spotify_credentials_args ~client_id ~client_secret
    in
    let%bind.Or_error () = Base_path.instantiate source_path in
    let official_api_args = if use_official_api then [ "--use-official-api" ] else [] in
    let config_args = if use_config then [ "--config" ] else [] in
    let args =
      ("download" :: queries)
      @ [ "--format"; "mp3"; "--output"; output_template ]
      @ config_args
      @ credential_args
      @ official_api_args
    in
    let spotdl_path = resolve_executable_path spotdl_path in
    let%bind.Or_error status =
      Or_error.try_with (fun () ->
        let process =
          Core_unix.create_process_with_fds
            ~working_dir:(Base_path.get_path source_path)
            ~prog:spotdl_path
            ~args
            ~stdin:(Use_this Core_unix.stdin)
            ~stdout:(Use_this Core_unix.stdout)
            ~stderr:(Use_this Core_unix.stderr)
            ()
        in
        Core_unix.waitpid process.pid)
      |> Or_error.tag ~tag:[%string "Unable to run %{spotdl_path}"]
    in
    Core_unix.Exit_or_signal.or_error status |> Or_error.tag ~tag:"spotDL download failed")
;;
