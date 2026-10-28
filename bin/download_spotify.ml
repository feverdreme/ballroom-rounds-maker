open! Core

let default_config_path () = Filename.concat (Sys.getenv_exn "HOME") ".spotdl/config.json"

let download_command =
  Command.basic_or_error
    ~summary:"Download Spotify tracks as MP3 files into a source directory"
    (let%map_open.Command source_dir =
       flag
         "-source-path"
         (required Filename_unix.arg_type)
         ~doc:"DIR directory in which to store downloaded MP3 files"
     and spotdl_path =
       flag
         "-spotdl-path"
         (optional_with_default "spotdl" string)
         ~doc:"PATH path to the spotdl binary (default: spotdl)"
     and config_path =
       flag
         "-spotdl-config"
         (optional_with_default (default_config_path ()) Filename_unix.arg_type)
         ~doc:"PATH spotDL configuration file to load (default: ~/.spotdl/config.json)"
     and client_id =
       flag
         "-spotify-client-id"
         (optional string)
         ~doc:"ID Spotify developer application client ID"
     and client_secret =
       flag
         "-spotify-client-secret"
         (optional string)
         ~doc:"SECRET Spotify developer application client secret"
     and use_official_api =
       flag
         "-use-official-spotify-api"
         no_arg
         ~doc:" use Spotify's official Web API client"
     and queries = anon (sequence ("SPOTIFY_URL" %: string)) in
     fun () ->
       let%bind.Or_error source_path = Rounds_lib.Base_path.create ~base_dir:source_dir in
       Rounds_lib.Spotdl.download
         ~spotdl_path
         ~config_path
         ?client_id
         ?client_secret
         ~use_official_api
         ~queries
         ~source_path
         ())
;;

let () = Command_unix.run download_command
