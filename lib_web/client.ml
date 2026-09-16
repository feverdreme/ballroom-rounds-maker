open! Core
open! Async_kernel
open! Bonsai_web
open Bonsai.Let_syntax
module Http = Async_js.Http
module Protocol = Rounds_web_protocol.Protocol
module Round = Rounds_model.Round
module Raw_vdom = Virtual_dom.Vdom

(* Keep the view code compact while using the current labelled Virtual_dom constructors. *)
module Vdom = struct
  module Attr = Raw_vdom.Attr

  module Node = struct
    include Raw_vdom.Node

    let aside attrs children = Raw_vdom.Node.aside ~attrs children
    let button attrs children = Raw_vdom.Node.button ~attrs children
    let div attrs children = Raw_vdom.Node.div ~attrs children
    let h1 attrs children = Raw_vdom.Node.h1 ~attrs children
    let h2 attrs children = Raw_vdom.Node.h2 ~attrs children
    let header attrs children = Raw_vdom.Node.header ~attrs children
    let input attrs _children = Raw_vdom.Node.input ~attrs ()
    let label attrs children = Raw_vdom.Node.label ~attrs children
    let main attrs children = Raw_vdom.Node.main ~attrs children
    let p attrs children = Raw_vdom.Node.p ~attrs children
    let section attrs children = Raw_vdom.Node.section ~attrs children
    let span attrs children = Raw_vdom.Node.span ~attrs children
    let strong attrs children = Raw_vdom.Node.strong ~attrs children
  end
end

module Model = struct
  type song_form =
    { index : int option
    ; search : string
    ; filepath : string
    ; duration : string
    ; fade_in : string
    ; fade_out : string
    ; name : string
    ; dance : string
    ; error : string option
    }

  type break_form =
    { index : int option
    ; duration : string
    ; error : string option
    }

  type dialog =
    | No_dialog
    | Song_form of song_form
    | Break_form of break_form
    | Confirm_delete of int
    | Confirm_leave

  type editor =
    { path : string option
    ; saved : Round.t
    ; draft : Round.t
    }

  type page =
    | Configure
    | Dashboard
    | Editor

  type t =
    { workspace : Protocol.workspace
    ; catalog : Protocol.initialize_result option
    ; page : page
    ; editor : editor option
    ; dialog : dialog
    ; message : string option
    ; error : string option
    ; loading : bool
    ; round_search : string
    ; dragging : int option
    }

  let default =
    { workspace = { rounds_dir = "rounds"; source_dir = "." }
    ; catalog = None
    ; page = Configure
    ; editor = None
    ; dialog = No_dialog
    ; message = None
    ; error = None
    ; loading = false
    ; round_search = ""
    ; dragging = None
    }
  ;;
end

module Action = struct
  type t =
    | Set_rounds_dir of string
    | Set_source_dir of string
    | Start_request
    | Initialized of Protocol.initialize_result Or_error.t
    | Set_round_search of string
    | Change_workspace
    | New_round
    | Loaded of string * Round.t Or_error.t
    | Rounds_refreshed of Protocol.list_rounds_result Or_error.t
    | Set_round_name of string
    | Songs_refreshed of Model.song_form * Protocol.list_songs_result Or_error.t
    | Set_song_search of string
    | Set_song_filepath of string
    | Set_song_duration of string
    | Set_song_fade_in of string
    | Set_song_fade_out of string
    | Set_song_name of string
    | Set_song_dance of string
    | Apply_song
    | Open_break of int option
    | Set_break_duration of string
    | Apply_break
    | Ask_delete of int
    | Delete_event of int
    | Move_event of int * int
    | Start_drag of int
    | Drop_on of int
    | Cancel_dialog
    | Request_dashboard
    | Leave_editor
    | Saved of Protocol.save_result Or_error.t
end

open Model
open Action

let round_equal left right = Sexp.equal (Round.sexp_of_t left) (Round.sexp_of_t right)

let editor_is_dirty (editor : Model.editor) =
  Option.is_none editor.path || not (round_equal editor.saved editor.draft)
;;

let parse_nonnegative label string =
  match Int.of_string (String.strip string) with
  | value when value >= 0 -> Ok value
  | _ | (exception _) -> Or_error.errorf "%s must be a non-negative whole number" label
;;

let replace_at list index value =
  List.mapi list ~f:(fun current existing -> if current = index then value else existing)
;;

let move_event events from_index to_index =
  if from_index = to_index
     || from_index < 0
     || to_index < 0
     || from_index >= List.length events
     || to_index >= List.length events
  then events
  else (
    let event = List.nth_exn events from_index in
    let without = List.filteri events ~f:(fun index _ -> index <> from_index) in
    let target = to_index in
    List.take without target @ [ event ] @ List.drop without target)
;;

let update_editor model ~f =
  match model.Model.editor with
  | None -> model
  | Some editor -> { model with editor = Some (f editor); message = None; error = None }
;;

let update_song_form model ~f =
  match model.Model.dialog with
  | Song_form form -> { model with dialog = Song_form (f form) }
  | _ -> model
;;

let update_break_form model ~f =
  match model.Model.dialog with
  | Break_form form -> { model with dialog = Break_form (f form) }
  | _ -> model
;;

let empty_song_form index =
  Model.
    { index
    ; search = ""
    ; filepath = ""
    ; duration = "90"
    ; fade_in = "0"
    ; fade_out = "5"
    ; name = ""
    ; dance = ""
    ; error = None
    }
;;

let song_form_of_event index = function
  | Round.Event.Song { song_data; name; dance } ->
    Model.
      { index = Some index
      ; search = ""
      ; filepath = song_data.filepath
      ; duration = Int.to_string song_data.duration
      ; fade_in = Int.to_string song_data.fade_in
      ; fade_out = Int.to_string song_data.fade_out
      ; name = Option.value name ~default:""
      ; dance = Option.value dance ~default:""
      ; error = None
      }
  | Break _ -> empty_song_form (Some index)
;;

let break_form_of_event index = function
  | Round.Event.Break break ->
    Model.{ index = Some index; duration = Int.to_string break.duration; error = None }
  | Song _ -> Model.{ index = Some index; duration = "10"; error = None }
;;

let apply_action _context (model : Model.t) (action : Action.t) =
  match action with
  | Set_rounds_dir rounds_dir ->
    { model with workspace = { model.workspace with rounds_dir }; error = None }
  | Set_source_dir source_dir ->
    { model with workspace = { model.workspace with source_dir }; error = None }
  | Start_request -> { model with loading = true; error = None; message = None }
  | Initialized (Error error) ->
    { model with loading = false; error = Some (Error.to_string_hum error) }
  | Initialized (Ok catalog) ->
    { model with
      catalog = Some catalog
    ; page = Dashboard
    ; editor = None
    ; dialog = No_dialog
    ; loading = false
    ; error = None
    ; message = None
    }
  | Set_round_search round_search -> { model with round_search }
  | Change_workspace ->
    { model with
      page = Configure
    ; catalog = None
    ; editor = None
    ; dialog = No_dialog
    ; error = None
    }
  | New_round ->
    let round = Round.{ name = "Untitled round"; events = [] } in
    { model with
      page = Editor
    ; editor = Some { path = None; saved = round; draft = round }
    ; dialog = No_dialog
    ; error = None
    ; message = None
    }
  | Loaded (_, Error error) ->
    { model with loading = false; error = Some (Error.to_string_hum error) }
  | Loaded (path, Ok round) ->
    { model with
      page = Editor
    ; editor = Some { path = Some path; saved = round; draft = round }
    ; dialog = No_dialog
    ; loading = false
    ; error = None
    ; message = None
    }
  | Rounds_refreshed (Error error) ->
    { model with loading = false; error = Some (Error.to_string_hum error) }
  | Rounds_refreshed (Ok rounds) ->
    let catalog = Option.map model.catalog ~f:(fun catalog -> { catalog with rounds }) in
    { model with
      catalog
    ; page = Dashboard
    ; editor = None
    ; dialog = No_dialog
    ; loading = false
    ; error = None
    ; message = None
    }
  | Set_round_name name ->
    update_editor model ~f:(fun editor ->
      { editor with draft = { editor.draft with name } })
  | Songs_refreshed (_, Error error) ->
    { model with loading = false; error = Some (Error.to_string_hum error) }
  | Songs_refreshed (form, Ok songs) ->
    let catalog = Option.map model.catalog ~f:(fun catalog -> { catalog with songs }) in
    { model with catalog; dialog = Song_form form; loading = false; error = None }
  | Set_song_search search -> update_song_form model ~f:(fun form -> { form with search })
  | Set_song_filepath filepath ->
    update_song_form model ~f:(fun form -> { form with filepath })
  | Set_song_duration duration ->
    update_song_form model ~f:(fun form -> { form with duration; error = None })
  | Set_song_fade_in fade_in ->
    update_song_form model ~f:(fun form -> { form with fade_in; error = None })
  | Set_song_fade_out fade_out ->
    update_song_form model ~f:(fun form -> { form with fade_out; error = None })
  | Set_song_name name -> update_song_form model ~f:(fun form -> { form with name })
  | Set_song_dance dance -> update_song_form model ~f:(fun form -> { form with dance })
  | Apply_song ->
    (match model.dialog, model.editor with
     | Song_form form, Some editor ->
       let result =
         let%bind.Or_error duration = parse_nonnegative "Duration" form.duration in
         let%bind.Or_error fade_in = parse_nonnegative "Fade in" form.fade_in in
         let%bind.Or_error fade_out = parse_nonnegative "Fade out" form.fade_out in
         if String.is_empty form.filepath
         then Or_error.error_string "Choose a song file"
         else Round.Song.create ~filepath:form.filepath ~duration ~fade_in ~fade_out
       in
       (match result with
        | Error error ->
          update_song_form model ~f:(fun form ->
            { form with error = Some (Error.to_string_hum error) })
        | Ok song_data ->
          let optional string =
            let string = String.strip string in
            if String.is_empty string then None else Some string
          in
          let event =
            Round.Event.Song
              { song_data; name = optional form.name; dance = optional form.dance }
          in
          let events =
            match form.index with
            | None -> editor.draft.events @ [ event ]
            | Some index -> replace_at editor.draft.events index event
          in
          { model with
            editor = Some { editor with draft = { editor.draft with events } }
          ; dialog = No_dialog
          ; message = None
          })
     | _ -> model)
  | Open_break index ->
    let form =
      match index, model.editor with
      | Some index, Some editor ->
        break_form_of_event index (List.nth_exn editor.draft.events index)
      | _ -> Model.{ index; duration = "10"; error = None }
    in
    { model with dialog = Break_form form }
  | Set_break_duration duration ->
    update_break_form model ~f:(fun form -> { form with duration; error = None })
  | Apply_break ->
    (match model.dialog, model.editor with
     | Break_form form, Some editor ->
       (match parse_nonnegative "Break duration" form.duration with
        | Error error ->
          update_break_form model ~f:(fun form ->
            { form with error = Some (Error.to_string_hum error) })
        | Ok duration ->
          let event = Round.Event.Break { duration } in
          let events =
            match form.index with
            | None -> editor.draft.events @ [ event ]
            | Some index -> replace_at editor.draft.events index event
          in
          { model with
            editor = Some { editor with draft = { editor.draft with events } }
          ; dialog = No_dialog
          ; message = None
          })
     | _ -> model)
  | Ask_delete index -> { model with dialog = Confirm_delete index }
  | Delete_event index ->
    update_editor { model with dialog = No_dialog } ~f:(fun editor ->
      let events =
        List.filteri editor.draft.events ~f:(fun current _ -> current <> index)
      in
      { editor with draft = { editor.draft with events } })
  | Move_event (from_index, to_index) ->
    update_editor model ~f:(fun editor ->
      let events = move_event editor.draft.events from_index to_index in
      { editor with draft = { editor.draft with events } })
  | Start_drag index -> { model with dragging = Some index }
  | Drop_on index ->
    (match model.dragging with
     | None -> model
     | Some from_index ->
       let model = { model with dragging = None } in
       update_editor model ~f:(fun editor ->
         let events = move_event editor.draft.events from_index index in
         { editor with draft = { editor.draft with events } }))
  | Cancel_dialog -> { model with dialog = No_dialog }
  | Request_dashboard ->
    (match model.editor with
     | Some editor when editor_is_dirty editor -> { model with dialog = Confirm_leave }
     | _ -> { model with page = Dashboard; editor = None; dialog = No_dialog })
  | Leave_editor ->
    { model with
      page = Dashboard
    ; editor = None
    ; dialog = No_dialog
    ; error = None
    ; message = None
    }
  | Saved (Error error) ->
    { model with loading = false; error = Some (Error.to_string_hum error) }
  | Saved (Ok saved) ->
    (match model.editor with
     | None -> { model with loading = false }
     | Some editor ->
       (* CR aide for jeffrey: The request saved the draft captured by [save_effect], but
          this reducer marks the editor's current draft as saved. Since the form remains
          editable while [loading], edits made during the request are falsely shown as
          saved and can be lost on navigation. Carry the submitted round in [Saved], or
          disable every editing action until the response arrives. *)
       let editor = { editor with path = Some saved.path; saved = editor.draft } in
       let summary =
         Protocol.
           { path = saved.path
           ; name = editor.draft.name
           ; event_count = List.length editor.draft.events
           }
       in
       let catalog =
         Option.map model.catalog ~f:(fun catalog ->
           let rounds =
             summary
             :: List.filter catalog.rounds ~f:(fun existing ->
               not (String.equal existing.path saved.path))
             |> List.sort ~compare:(fun left right -> String.compare left.name right.name)
           in
           { catalog with rounds })
       in
       { model with
         editor = Some editor
       ; catalog
       ; loading = false
       ; error = None
       ; message = Some ("Saved to " ^ saved.path)
       })
;;

let post ~path ~sexp ~of_sexp =
  let open Deferred.Let_syntax in
  let%map response =
    Http.request
      ~headers:[ "Content-Type", "application/sexp" ]
      ~url:path
      ~response_type:Http.Response_type.Text
      (Post (Some (String (Sexp.to_string sexp))))
  in
  match response with
  | Error error -> Error error
  | Ok response ->
    Or_error.try_with (fun () ->
      Js_of_ocaml.Js.to_string response.content |> Sexp.of_string |> of_sexp)
    |> (function
     | Ok response -> response
     | Error error -> Error error)
;;

let initialize_effect workspace inject =
  let open Effect.Let_syntax in
  let%bind () = inject Action.Start_request in
  let%bind response =
    Effect.of_deferred_fun
      (fun workspace ->
        post
          ~path:"/api/initialize"
          ~sexp:(Protocol.sexp_of_initialize_request workspace)
          ~of_sexp:(Or_error.t_of_sexp Protocol.initialize_result_of_sexp))
      workspace
  in
  inject (Initialized response)
;;

let refresh_rounds_effect workspace inject =
  let open Effect.Let_syntax in
  let%bind () = inject Action.Start_request in
  let%bind response =
    Effect.of_deferred_fun
      (fun workspace ->
        post
          ~path:"/api/rounds"
          ~sexp:(Protocol.sexp_of_list_rounds_request workspace)
          ~of_sexp:(Or_error.t_of_sexp Protocol.list_rounds_result_of_sexp))
      workspace
  in
  inject (Rounds_refreshed response)
;;

let refresh_songs_effect workspace form inject =
  let open Effect.Let_syntax in
  let%bind () = inject Action.Start_request in
  let%bind response =
    Effect.of_deferred_fun
      (fun workspace ->
        post
          ~path:"/api/songs"
          ~sexp:(Protocol.sexp_of_list_songs_request workspace)
          ~of_sexp:(Or_error.t_of_sexp Protocol.list_songs_result_of_sexp))
      workspace
  in
  inject (Songs_refreshed (form, response))
;;

let load_effect workspace path inject =
  let open Effect.Let_syntax in
  let%bind () = inject Action.Start_request in
  let request = Protocol.{ workspace; path } in
  let%bind response =
    Effect.of_deferred_fun
      (fun request ->
        post
          ~path:"/api/load"
          ~sexp:(Protocol.sexp_of_load_request request)
          ~of_sexp:(Or_error.t_of_sexp Round.t_of_sexp))
      request
  in
  inject (Loaded (path, response))
;;

let save_effect workspace (editor : Model.editor) inject =
  let open Effect.Let_syntax in
  let%bind () = inject Action.Start_request in
  let request = Protocol.{ workspace; path = editor.path; round = editor.draft } in
  let%bind response =
    Effect.of_deferred_fun
      (fun request ->
        post
          ~path:"/api/save"
          ~sexp:(Protocol.sexp_of_save_request request)
          ~of_sexp:(Or_error.t_of_sexp Protocol.save_result_of_sexp))
      request
  in
  inject (Saved response)
;;

let attr_class name = Vdom.Attr.class_ name
let text = Vdom.Node.text

let button ?(kind = "") ?(disabled = false) ~label ~on_click () =
  let class_name = String.strip ("button " ^ kind) in
  Vdom.Node.button
    [ attr_class class_name
    ; Vdom.Attr.disabled' disabled
    ; Vdom.Attr.on_click (fun _ -> on_click)
    ]
    [ text label ]
;;

let input_field ?(type_ = "text") ?placeholder ~label ~value ~on_input () =
  let attributes =
    [ Vdom.Attr.type_ type_
    ; Vdom.Attr.value value
    ; Vdom.Attr.on_input (fun _ value -> on_input value)
    ]
    @ Option.value_map placeholder ~default:[] ~f:(fun value ->
      [ Vdom.Attr.placeholder value ])
  in
  Vdom.Node.div
    [ attr_class "field" ]
    [ Vdom.Node.label [] [ text label ]; Vdom.Node.input attributes [] ]
;;

let error_view = function
  | None -> Vdom.Node.none
  | Some error -> Vdom.Node.div [ attr_class "error" ] [ text error ]
;;

let masthead ?action () =
  let action = Option.to_list action in
  Vdom.Node.header
    [ attr_class "masthead" ]
    ([ Vdom.Node.div
         []
         [ Vdom.Node.div [ attr_class "eyebrow" ] [ text "Local competition audio" ]
         ; Vdom.Node.h1 [] [ text "Ballroom Rounds Maker" ]
         ; Vdom.Node.div
             [ attr_class "subtitle" ]
             [ text "Shape the music for your next round." ]
         ]
     ]
     @ action)
;;

let configure_view model inject =
  Vdom.Node.div
    [ attr_class "shell" ]
    [ masthead ()
    ; Vdom.Node.main
        [ attr_class "panel workspace" ]
        [ Vdom.Node.h2 [] [ text "Choose your workspace" ]
        ; Vdom.Node.p
            [ attr_class "muted" ]
            [ text
                "The local server reads audio and round files from these folders. \
                 Nothing is uploaded."
            ]
        ; input_field
            ~label:"Rounds directory"
            ~value:model.Model.workspace.rounds_dir
            ~placeholder:"rounds"
            ~on_input:(fun value -> inject (Set_rounds_dir value))
            ()
        ; input_field
            ~label:"Source audio directory"
            ~value:model.workspace.source_dir
            ~placeholder:"."
            ~on_input:(fun value -> inject (Set_source_dir value))
            ()
        ; error_view model.error
        ; Vdom.Node.div
            [ attr_class "actions" ]
            [ button
                ~kind:"primary"
                ~disabled:model.loading
                ~label:(if model.loading then "Opening…" else "Open workspace")
                ~on_click:(initialize_effect model.workspace inject)
                ()
            ]
        ]
    ]
;;

let dashboard_view model catalog inject =
  let query = String.lowercase (String.strip model.Model.round_search) in
  let rounds =
    if String.is_empty query
    then catalog.Protocol.rounds
    else
      List.filter catalog.rounds ~f:(fun round ->
        String.is_substring (String.lowercase round.name) ~substring:query
        || String.is_substring (String.lowercase round.path) ~substring:query)
  in
  let cards =
    if List.is_empty rounds
    then
      [ Vdom.Node.div
          [ attr_class "empty" ]
          [ text
              (if List.is_empty catalog.rounds
               then "No rounds here yet. Create the first one."
               else "No matching rounds.")
          ]
      ]
    else
      List.map rounds ~f:(fun round ->
        (* CR-soon aide for jeffrey: Round cards remain clickable while a load is in
           flight. Two quick clicks can complete out of order and open the first round
           after the user selected the second. Disable these while [model.loading] or
           attach an id to each request and discard stale responses. *)
        Vdom.Node.button
          [ attr_class "round-card"
          ; Vdom.Attr.on_click (fun _ -> load_effect model.workspace round.path inject)
          ]
          [ Vdom.Node.strong [] [ text round.name ]
          ; Vdom.Node.div
              [ attr_class "muted" ]
              [ text
                  (sprintf
                     "%d event%s · %s"
                     round.event_count
                     (if round.event_count = 1 then "" else "s")
                     round.path)
              ]
          ])
  in
  Vdom.Node.div
    [ attr_class "shell" ]
    [ masthead
        ~action:(button ~label:"Change folders" ~on_click:(inject Change_workspace) ())
        ()
    ; Vdom.Node.main
        [ attr_class "panel" ]
        [ Vdom.Node.div
            [ attr_class "toolbar" ]
            [ Vdom.Node.div
                []
                [ Vdom.Node.h2 [] [ text "Rounds" ]
                ; Vdom.Node.div [ attr_class "muted" ] [ text model.workspace.rounds_dir ]
                ]
            ; button ~kind:"primary" ~label:"New round" ~on_click:(inject New_round) ()
            ]
        ; input_field
            ~label:"Search rounds"
            ~value:model.round_search
            ~placeholder:"Name or filename"
            ~on_input:(fun value -> inject (Set_round_search value))
            ()
        ; error_view model.error
        ; Vdom.Node.div [ attr_class "round-grid" ] cards
        ]
    ]
;;

let event_description = function
  | Round.Event.Break break -> "Break", sprintf "%d seconds of silence" break.duration
  | Song { song_data; name; dance } ->
    let title = Option.value name ~default:(Filename.basename song_data.filepath) in
    let details =
      [ Option.value dance ~default:"Song"
      ; sprintf "%ds" song_data.duration
      ; sprintf "%ds in / %ds out" song_data.fade_in song_data.fade_out
      ; song_data.filepath
      ]
      |> String.concat ~sep:" · "
    in
    title, details
;;

let event_view ~event_count ~open_song index event inject =
  let title, details = event_description event in
  let edit_action =
    match event with
    | Round.Event.Song _ -> open_song (song_form_of_event index event)
    | Break _ -> inject (Open_break (Some index))
  in
  Vdom.Node.div
    [ attr_class "event"
    ; Vdom.Attr.draggable true
    ; Vdom.Attr.on_dragstart (fun _ -> inject (Start_drag index))
    ; Vdom.Attr.on_dragover (fun event ->
        Js_of_ocaml.Dom.preventDefault event;
        Effect.Ignore)
    ; Vdom.Attr.on_drop (fun event ->
        Js_of_ocaml.Dom.preventDefault event;
        inject (Drop_on index))
    ]
    [ Vdom.Node.div [ attr_class "event-index" ] [ text (Int.to_string (index + 1)) ]
    ; Vdom.Node.div
        []
        [ Vdom.Node.div [ attr_class "event-title" ] [ text title ]
        ; Vdom.Node.div [ attr_class "event-meta" ] [ text details ]
        ]
    ; Vdom.Node.div
        [ attr_class "event-actions" ]
        [ button
            ~kind:"icon"
            ~disabled:(index = 0)
            ~label:"↑"
            ~on_click:(inject (Move_event (index, index - 1)))
            ()
        ; button
            ~kind:"icon"
            ~disabled:(index = event_count - 1)
            ~label:"↓"
            ~on_click:(inject (Move_event (index, index + 1)))
            ()
        ; button ~label:"Edit" ~on_click:edit_action ()
        ; button ~kind:"danger" ~label:"Delete" ~on_click:(inject (Ask_delete index)) ()
        ]
    ]
;;

let song_dialog form songs inject =
  let query = String.lowercase (String.strip form.Model.search) in
  let matches =
    songs
    |> List.filter ~f:(fun path ->
      String.is_empty query
      || String.is_substring (String.lowercase path) ~substring:query)
    |> Fn.flip List.take 80
  in
  let choices =
    if List.is_empty matches
    then [ Vdom.Node.div [ attr_class "empty" ] [ text "No matching audio files." ] ]
    else
      List.map matches ~f:(fun path ->
        Vdom.Node.button
          [ Vdom.Attr.classes
              ([ "song-choice" ]
               @ if String.equal path form.filepath then [ "selected" ] else [])
          ; Vdom.Attr.on_click (fun _ -> inject (Set_song_filepath path))
          ]
          [ text path ])
  in
  Vdom.Node.div
    [ attr_class "dialog-backdrop" ]
    [ Vdom.Node.div
        [ attr_class "dialog" ]
        [ Vdom.Node.h2
            []
            [ text (if Option.is_some form.index then "Edit song" else "Add song") ]
        ; input_field
            ~label:"Find audio"
            ~value:form.search
            ~placeholder:"Type to filter"
            ~on_input:(fun value -> inject (Set_song_search value))
            ()
        ; Vdom.Node.div [ attr_class "search-results" ] choices
        ; Vdom.Node.div
            [ attr_class "event-meta" ]
            [ text
                ("Selected: "
                 ^ if String.is_empty form.filepath then "none" else form.filepath)
            ]
        ; input_field
            ~type_:"number"
            ~label:"Duration (seconds)"
            ~value:form.duration
            ~on_input:(fun value -> inject (Set_song_duration value))
            ()
        ; input_field
            ~type_:"number"
            ~label:"Fade in (seconds)"
            ~value:form.fade_in
            ~on_input:(fun value -> inject (Set_song_fade_in value))
            ()
        ; input_field
            ~type_:"number"
            ~label:"Fade out (seconds)"
            ~value:form.fade_out
            ~on_input:(fun value -> inject (Set_song_fade_out value))
            ()
        ; input_field
            ~label:"Display name (optional)"
            ~value:form.name
            ~on_input:(fun value -> inject (Set_song_name value))
            ()
        ; input_field
            ~label:"Dance (optional)"
            ~value:form.dance
            ~on_input:(fun value -> inject (Set_song_dance value))
            ()
        ; error_view form.error
        ; Vdom.Node.div
            [ attr_class "actions" ]
            [ button ~kind:"primary" ~label:"Apply song" ~on_click:(inject Apply_song) ()
            ; button ~label:"Cancel" ~on_click:(inject Cancel_dialog) ()
            ]
        ]
    ]
;;

let break_dialog form inject =
  Vdom.Node.div
    [ attr_class "dialog-backdrop" ]
    [ Vdom.Node.div
        [ attr_class "dialog" ]
        [ Vdom.Node.h2
            []
            [ text (if Option.is_some form.Model.index then "Edit break" else "Add break")
            ]
        ; input_field
            ~type_:"number"
            ~label:"Break duration (seconds)"
            ~value:form.duration
            ~on_input:(fun value -> inject (Set_break_duration value))
            ()
        ; error_view form.error
        ; Vdom.Node.div
            [ attr_class "actions" ]
            [ button
                ~kind:"primary"
                ~label:"Apply break"
                ~on_click:(inject Apply_break)
                ()
            ; button ~label:"Cancel" ~on_click:(inject Cancel_dialog) ()
            ]
        ]
    ]
;;

let confirm_dialog ~title ~body ~confirm_label ~on_confirm inject =
  Vdom.Node.div
    [ attr_class "dialog-backdrop" ]
    [ Vdom.Node.div
        [ attr_class "dialog" ]
        [ Vdom.Node.h2 [] [ text title ]
        ; Vdom.Node.p [] [ text body ]
        ; Vdom.Node.div
            [ attr_class "actions" ]
            [ button ~kind:"danger" ~label:confirm_label ~on_click:on_confirm ()
            ; button ~label:"Cancel" ~on_click:(inject Cancel_dialog) ()
            ]
        ]
    ]
;;

let editor_view model catalog editor inject =
  let dirty = editor_is_dirty editor in
  let open_song form = refresh_songs_effect model.workspace form inject in
  let events =
    if List.is_empty editor.Model.draft.events
    then
      [ Vdom.Node.div
          [ attr_class "empty" ]
          [ text "No events yet. Add a song or a break." ]
      ]
    else
      List.mapi editor.draft.events ~f:(fun index event ->
        event_view
          ~event_count:(List.length editor.draft.events)
          ~open_song
          index
          event
          inject)
  in
  let dialog =
    match model.Model.dialog with
    | No_dialog -> Vdom.Node.none
    | Song_form form -> song_dialog form catalog.Protocol.songs inject
    | Break_form form -> break_dialog form inject
    | Confirm_delete index ->
      confirm_dialog
        ~title:"Delete event?"
        ~body:"This removes the event from the draft round."
        ~confirm_label:"Delete event"
        ~on_confirm:(inject (Delete_event index))
        inject
    | Confirm_leave ->
      let on_confirm =
        let open Effect.Let_syntax in
        let%bind () = inject Leave_editor in
        refresh_rounds_effect model.workspace inject
      in
      confirm_dialog
        ~title:"Discard unsaved changes?"
        ~body:"Your changes since the last save will be lost."
        ~confirm_label:"Discard changes"
        ~on_confirm
        inject
  in
  Vdom.Node.div
    [ attr_class "shell" ]
    [ masthead
        ~action:
          (button
             ~label:"All rounds"
             ~on_click:
               (if dirty
                then inject Request_dashboard
                else refresh_rounds_effect model.workspace inject)
             ())
        ()
    ; Vdom.Node.main
        [ attr_class "editor-grid" ]
        [ Vdom.Node.section
            [ attr_class "panel" ]
            [ input_field
                ~label:"Round name"
                ~value:editor.draft.name
                ~on_input:(fun value -> inject (Set_round_name value))
                ()
            ; Vdom.Node.div [ attr_class "event-list" ] events
            ]
        ; Vdom.Node.aside
            [ attr_class "panel sidebar" ]
            [ Vdom.Node.h2 [] [ text "Build the round" ]
            ; Vdom.Node.p
                [ attr_class "muted" ]
                [ text "Drag events to reorder them, or use the arrow buttons." ]
            ; Vdom.Node.div
                [ attr_class "actions" ]
                [ button ~label:"Add song" ~on_click:(open_song (empty_song_form None)) ()
                ; button ~label:"Add break" ~on_click:(inject (Open_break None)) ()
                ]
            ; Vdom.Node.div [ attr_class "field" ] []
            ; button
                ~kind:"primary"
                ~disabled:(model.loading || not dirty)
                ~label:(if model.loading then "Saving…" else "Save round")
                ~on_click:(save_effect model.workspace editor inject)
                ()
            ; Vdom.Node.div
                [ attr_class "status" ]
                [ (match model.message with
                   | Some message ->
                     Vdom.Node.span [ attr_class "success" ] [ text message ]
                   | None ->
                     if dirty then text "Unsaved changes" else text "All changes saved")
                ]
            ; error_view model.error
            ]
        ]
    ; dialog
    ]
;;

let app (local_ graph) =
  let model, inject =
    Bonsai.state_machine ~default_model:Model.default ~apply_action graph
  in
  let%arr model and inject in
  match model.Model.page, model.catalog, model.editor with
  | Configure, _, _ -> configure_view model inject
  | Dashboard, Some catalog, _ -> dashboard_view model catalog inject
  | Editor, Some catalog, Some editor -> editor_view model catalog editor inject
  | _ -> configure_view model inject
;;

let () = Bonsai_web.Start.start app
