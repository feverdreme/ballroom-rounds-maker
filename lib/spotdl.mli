open! Core

(** Download the Spotify [queries] as MP3 files into [source_path] using spotDL.
    [client_id] and [client_secret] must be supplied together when using a Spotify
    developer application. [use_config] loads spotDL's default config file, which
    spotDL locates itself (usually [~/.spotdl/config.json]). *)
val download
  :  ?spotdl_path:string
  -> ?use_config:bool
  -> ?client_id:string
  -> ?client_secret:string
  -> ?use_official_api:bool
  -> queries:string list
  -> source_path:Base_path.t
  -> unit
  -> unit Or_error.t
