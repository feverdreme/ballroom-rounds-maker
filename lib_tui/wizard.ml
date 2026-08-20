open! Core
open! Async
open! Bonsai_term
open Bonsai.Let_syntax
module Round = Rounds_lib.Round
module Base_path = Rounds_lib.Base_path

let song_extensions = [ ".mp3"; ".wav"; ".m4a" ]

(* A wizard "step" is one screen. Each step's continuation is a plain closure returning
   the next step, so the whole flow is built compositionally without a giant enumerated
   step type per screen. *)
module Model = struct
  (* [on_back] fields are thunks, not plain [t] values: several steps (e.g. [create_menu],
     [edit_menu]) build their [on_back] from a closure that, if evaluated, calls back into
     the very function constructing the step. A plain [t] field would force that closure
     immediately (OCaml evaluates arguments eagerly), causing unbounded recursion the
     moment the step is built, before any key is ever pressed. A thunk defers it until
     Escape is actually pressed. *)
  type text_step =
    { t_label : string
    ; t_buffer : string
    ; t_error : string option
    ; t_info : string list
    ; t_on_submit : string -> t
    ; t_on_back : (unit -> t) option
    }

  and path_step =
    { p_label : string
    ; p_buffer : string
    ; p_error : string option
    ; p_info : string list
    ; p_suggestions : string list
    ; p_highlighted : int
    ; p_on_submit : string -> t
    ; p_on_back : (unit -> t) option
    }

  and select_step =
    { s_title : string list
    ; s_items : string list
    ; s_selected : int
    ; s_on_select : int -> t
    ; s_on_back : (unit -> t) option
    }

  and filter_select_step =
    { f_title : string list
    ; f_all_items : string list
    ; f_query : string
    ; f_highlighted : int
    ; f_on_select : string -> t
    ; f_on_back : (unit -> t) option
    }

  and message_step =
    { m_text : string list
    ; m_next : t
    }

  and confirm_step =
    { c_prompt : string
    ; c_on_yes : t
    ; c_on_no : t
    }

  and reorder_step =
    { r_events : Round.Event.t list
    ; r_cursor : int
    ; r_grabbed : bool
    ; r_on_done : Round.Event.t list -> t
    }

  and t =
    | Text of text_step
    | Path of path_step
    | Select of select_step
    | Filter_select of filter_select_step
    | Message of message_step
    | Confirm of confirm_step
    | Reorder of reorder_step
    | Quit
end

let text_step ~label ?(buffer = "") ?error ?(info = []) ?on_back ~on_submit () =
  Model.Text
    { t_label = label
    ; t_buffer = buffer
    ; t_error = error
    ; t_info = info
    ; t_on_submit = on_submit
    ; t_on_back = on_back
    }
;;

let path_step ~label ?(buffer = "") ?error ?(info = []) ?on_back ~on_submit () =
  Model.Path
    { p_label = label
    ; p_buffer = buffer
    ; p_error = error
    ; p_info = info
    ; p_suggestions = Dir_browser.path_completions buffer
    ; p_highlighted = 0
    ; p_on_submit = on_submit
    ; p_on_back = on_back
    }
;;

let select_step ~title ~items ?(selected = 0) ?on_back ~on_select () =
  Model.Select
    { s_title = title; s_items = items; s_selected = selected; s_on_select = on_select; s_on_back = on_back }
;;

let filter_select_step ~title ~items ?(query = "") ?on_back ~on_select () =
  Model.Filter_select
    { f_title = title
    ; f_all_items = items
    ; f_query = query
    ; f_highlighted = 0
    ; f_on_select = on_select
    ; f_on_back = on_back
    }
;;

let message ~text ~next = Model.Message { m_text = text; m_next = next }
let confirm ~prompt ~on_yes ~on_no = Model.Confirm { c_prompt = prompt; c_on_yes = on_yes; c_on_no = on_no }

let reorder_step ~events ~on_done () =
  Model.Reorder { r_events = events; r_cursor = 0; r_grabbed = false; r_on_done = on_done }
;;

let parse_int s =
  match Int.of_string (String.strip s) with
  | n -> Some n
  | exception _ -> None
;;

let events_lines events =
  if List.is_empty events
  then [ "(no events yet)" ]
  else List.mapi events ~f:(fun i ev -> sprintf "%d. %s" (i + 1) (Round.Event.to_string ev))
;;

let swap_adjacent events i j =
  if j < 0 || j >= List.length events
  then events
  else
    List.mapi events ~f:(fun idx ev ->
      if idx = i then List.nth_exn events j else if idx = j then List.nth_exn events i else ev)
;;

let filtered_items (fs : Model.filter_select_step) =
  if String.is_empty fs.f_query
  then fs.f_all_items
  else
    List.filter fs.f_all_items ~f:(fun item ->
      String.is_substring (String.lowercase item) ~substring:(String.lowercase fs.f_query))
;;

let rec ask_rounds_dir ?(buffer = "rounds") ?error () =
  path_step
    ~label:"Rounds directory (where round files live/get saved)"
    ~buffer
    ?error
    ~on_submit:(fun buffer ->
      match Base_path.create ~base_dir:(String.strip buffer) with
      | Error e -> ask_rounds_dir ~buffer ~error:(Error.to_string_hum e) ()
      | Ok rounds_dir -> ask_source_dir ~rounds_dir ())
    ()

and ask_source_dir ~rounds_dir ?(buffer = ".") ?error () =
  path_step
    ~label:"Source directory (where song audio files live)"
    ~buffer
    ?error
    ~info:[ sprintf "Rounds directory: %s" (Base_path.get_path rounds_dir) ]
    ~on_back:(fun () -> ask_rounds_dir ~buffer:(Base_path.get_path rounds_dir) ())
    ~on_submit:(fun buffer ->
      match Base_path.create ~base_dir:(String.strip buffer) with
      | Error e -> ask_source_dir ~rounds_dir ~buffer ~error:(Error.to_string_hum e) ()
      | Ok source_dir -> main_menu ~rounds_dir ~source_dir ())
    ()

and main_menu ~rounds_dir ~source_dir () =
  select_step
    ~title:[ "What would you like to do?" ]
    ~items:[ "Create new round"; "Edit existing round"; "Quit" ]
    ~on_select:(fun i ->
      match i with
      | 0 -> ask_round_name ~rounds_dir ~source_dir ()
      | 1 -> edit_pick_round ~rounds_dir ~source_dir ()
      | _ -> message ~text:[ "Goodbye!" ] ~next:Model.Quit)
    ()

and ask_round_name ~rounds_dir ~source_dir ?error () =
  text_step
    ~label:"Round name"
    ?error
    ~on_back:(fun () -> main_menu ~rounds_dir ~source_dir ())
    ~on_submit:(fun name ->
      let name = String.strip name in
      if String.is_empty name
      then ask_round_name ~rounds_dir ~source_dir ~error:"Name cannot be empty" ()
      else create_menu ~rounds_dir ~source_dir ~name ~events:[] ())
    ()

and create_menu ~rounds_dir ~source_dir ~name ~events () =
  let discard_confirm () =
    confirm
      ~prompt:"Discard this round? (y/n)"
      ~on_yes:(main_menu ~rounds_dir ~source_dir ())
      ~on_no:(create_menu ~rounds_dir ~source_dir ~name ~events ())
  in
  select_step
    ~title:(sprintf "Round: %s" name :: events_lines events)
    ~items:[ "Add song"; "Add break"; "Review events"; "Save & exit"; "Discard & exit" ]
    ~on_back:(fun () -> discard_confirm ())
    ~on_select:(fun i ->
      let back () = create_menu ~rounds_dir ~source_dir ~name ~events () in
      match i with
      | 0 ->
        song_pick_file
          ~source_dir
          ~on_song:(fun event ->
            create_menu ~rounds_dir ~source_dir ~name ~events:(events @ [ event ]) ())
          ~cancel:back
          ()
      | 1 ->
        ask_break_duration
          ~cancel:back
          ~on_break:(fun duration ->
            create_menu
              ~rounds_dir
              ~source_dir
              ~name
              ~events:(events @ [ Round.Event.Break { duration } ])
              ())
          ()
      | 2 -> message ~text:(events_lines events) ~next:(back ())
      | 3 -> save_round ~rounds_dir ~source_dir ~name ~events ~output_path:None ~on_cancel:back
      | _ -> discard_confirm ())
    ()

and save_round ~rounds_dir ~source_dir ~name ~events ~output_path ~on_cancel =
  match Base_path.instantiate rounds_dir with
  | Error e -> message ~text:[ Error.to_string_hum e ] ~next:(on_cancel ())
  | Ok () ->
    let path =
      match output_path with
      | Some p -> p
      | None -> Base_path.derive_path rounds_dir (Dir_browser.sanitize_filename name ^ ".sexp")
    in
    (match
       Or_error.try_with (fun () -> Round.save_to_file { Round.name; events } ~output_path:path)
     with
     | Ok () ->
       let note =
         match output_path with
         | Some _ -> sprintf "Saved to %s (round name is now '%s')" path name
         | None -> sprintf "Saved to %s" path
       in
       message ~text:[ note ] ~next:(main_menu ~rounds_dir ~source_dir ())
     | Error e -> message ~text:[ Error.to_string_hum e ] ~next:(on_cancel ()))

and ask_break_duration ~on_break ~cancel ?(buffer = "") ?error () =
  text_step
    ~label:"Break duration (seconds)"
    ~buffer
    ?error
    ~on_back:(fun () -> cancel ())
    ~on_submit:(fun s ->
      match parse_int s with
      | None ->
        ask_break_duration ~on_break ~cancel ~buffer:s ~error:"Enter a whole number of seconds" ()
      | Some duration -> on_break duration)
    ()

and song_pick_file ~source_dir ~on_song ~cancel () =
  match
    Dir_browser.list_files_by_extension ~root:(Base_path.get_path source_dir) ~extensions:song_extensions
  with
  | Error e -> message ~text:[ Error.to_string_hum e ] ~next:(cancel ())
  | Ok [] ->
    message
      ~text:[ sprintf "No audio files found under %s" (Base_path.get_path source_dir) ]
      ~next:(cancel ())
  | Ok items ->
    filter_select_step
      ~title:[ "Pick a song file" ]
      ~items
      ~on_back:(fun () -> cancel ())
      ~on_select:(fun filepath -> ask_song_duration ~filepath ~on_song ~cancel ())
      ()

and ask_song_duration ~filepath ~on_song ~cancel ?(buffer = "") ?error () =
  text_step
    ~label:(sprintf "Duration (seconds) for %s" filepath)
    ~buffer
    ?error
    ~on_back:(fun () -> cancel ())
    ~on_submit:(fun s ->
      match parse_int s with
      | None ->
        ask_song_duration
          ~filepath
          ~on_song
          ~cancel
          ~buffer:s
          ~error:"Enter a whole number of seconds"
          ()
      | Some duration -> ask_song_fade_in ~filepath ~duration ~on_song ~cancel ())
    ()

and ask_song_fade_in ~filepath ~duration ~on_song ~cancel ?(buffer = "0") ?error () =
  text_step
    ~label:"Fade in (seconds)"
    ~buffer
    ?error
    ~on_back:(fun () -> ask_song_duration ~filepath ~on_song ~cancel ~buffer:(Int.to_string duration) ())
    ~on_submit:(fun s ->
      let s = if String.is_empty (String.strip s) then "0" else s in
      match parse_int s with
      | None ->
        ask_song_fade_in
          ~filepath
          ~duration
          ~on_song
          ~cancel
          ~buffer:s
          ~error:"Enter a whole number of seconds"
          ()
      | Some fade_in -> ask_song_fade_out ~filepath ~duration ~fade_in ~on_song ~cancel ())
    ()

and ask_song_fade_out ~filepath ~duration ~fade_in ~on_song ~cancel ?(buffer = "0") ?error () =
  text_step
    ~label:"Fade out (seconds)"
    ~buffer
    ?error
    ~on_back:(fun () -> ask_song_fade_in ~filepath ~duration ~on_song ~cancel ~buffer:(Int.to_string fade_in) ())
    ~on_submit:(fun s ->
      let s = if String.is_empty (String.strip s) then "0" else s in
      match parse_int s with
      | None ->
        ask_song_fade_out
          ~filepath
          ~duration
          ~fade_in
          ~on_song
          ~cancel
          ~buffer:s
          ~error:"Enter a whole number of seconds"
          ()
      | Some fade_out ->
        (match Round.Song.create ~filepath ~duration ~fade_in ~fade_out with
         | Error e -> ask_song_duration ~filepath ~on_song ~cancel ~error:(Error.to_string_hum e) ()
         | Ok song -> ask_song_name ~song ~on_song ~cancel ()))
    ()

and ask_song_name ~song ~on_song ~cancel () =
  text_step
    ~label:"Display name (optional)"
    ~on_back:
      (fun () ->
        ask_song_fade_out
          ~filepath:song.Round.Song.filepath
          ~duration:song.duration
          ~fade_in:song.fade_in
          ~on_song
          ~cancel
          ~buffer:(Int.to_string song.fade_out)
          ())
    ~on_submit:(fun name_input ->
      let name = if String.is_empty (String.strip name_input) then None else Some name_input in
      ask_song_dance ~song ~name ~on_song ~cancel ())
    ()

and ask_song_dance ~song ~name ~on_song ~cancel () =
  text_step
    ~label:"Dance (optional)"
    ~on_back:(fun () -> ask_song_name ~song ~on_song ~cancel ())
    ~on_submit:(fun dance_input ->
      let dance = if String.is_empty (String.strip dance_input) then None else Some dance_input in
      on_song (Round.Event.Song { song; name; dance }))
    ()

and edit_pick_round ~rounds_dir ~source_dir () =
  match
    Dir_browser.list_files_by_extension_abs ~root:(Base_path.get_path rounds_dir) ~extensions:[ ".sexp" ]
  with
  | Error e -> message ~text:[ Error.to_string_hum e ] ~next:(main_menu ~rounds_dir ~source_dir ())
  | Ok [] ->
    message
      ~text:[ sprintf "No round files found under %s" (Base_path.get_path rounds_dir) ]
      ~next:(main_menu ~rounds_dir ~source_dir ())
  | Ok paths ->
    let basename_to_path = List.map paths ~f:(fun p -> Filename.basename p, p) in
    filter_select_step
      ~title:[ "Pick a round to edit" ]
      ~items:(List.map basename_to_path ~f:fst)
      ~on_back:(fun () -> main_menu ~rounds_dir ~source_dir ())
      ~on_select:(fun basename ->
        match List.Assoc.find basename_to_path basename ~equal:String.equal with
        | None -> edit_pick_round ~rounds_dir ~source_dir ()
        | Some path ->
          (match Or_error.try_with (fun () -> Round.read_from_file ~filepath:path) with
           | Error e ->
             message ~text:[ Error.to_string_hum e ] ~next:(edit_pick_round ~rounds_dir ~source_dir ())
           | Ok round -> edit_menu ~rounds_dir ~source_dir ~path ~name:round.name ~events:round.events ()))
      ()

and edit_menu ~rounds_dir ~source_dir ~path ~name ~events () =
  let back () = edit_menu ~rounds_dir ~source_dir ~path ~name ~events () in
  let discard_confirm () =
    confirm
      ~prompt:"Discard changes? (y/n)"
      ~on_yes:(main_menu ~rounds_dir ~source_dir ())
      ~on_no:(back ())
  in
  select_step
    ~title:(sprintf "Editing %s" name :: events_lines events)
    ~items:
      [ "Add song"
      ; "Add break"
      ; "Edit event"
      ; "Delete event"
      ; "Reorder events"
      ; "Rename round"
      ; "Save & exit"
      ; "Discard & exit"
      ]
    ~on_back:(fun () -> discard_confirm ())
    ~on_select:(fun i ->
      match i with
      | 0 ->
        song_pick_file
          ~source_dir
          ~on_song:(fun event ->
            edit_menu ~rounds_dir ~source_dir ~path ~name ~events:(events @ [ event ]) ())
          ~cancel:back
          ()
      | 1 ->
        ask_break_duration
          ~cancel:back
          ~on_break:(fun duration ->
            edit_menu
              ~rounds_dir
              ~source_dir
              ~path
              ~name
              ~events:(events @ [ Round.Event.Break { duration } ])
              ())
          ()
      | 2 ->
        ask_event_index
          ~events
          ~prompt:"Edit which event #?"
          ~on_index:(fun idx -> edit_event ~rounds_dir ~source_dir ~path ~name ~events ~idx ())
          ~cancel:back
          ()
      | 3 ->
        ask_event_index
          ~events
          ~prompt:"Delete which event #?"
          ~on_index:(fun idx ->
            confirm
              ~prompt:(sprintf "Delete event #%d? (y/n)" (idx + 1))
              ~on_yes:
                (edit_menu
                   ~rounds_dir
                   ~source_dir
                   ~path
                   ~name
                   ~events:(List.filteri events ~f:(fun j _ -> j <> idx))
                   ())
              ~on_no:(back ()))
          ~cancel:back
          ()
      | 4 ->
        if List.length events < 2
        then message ~text:[ "Need at least 2 events to reorder." ] ~next:(back ())
        else
          reorder_step
            ~events
            ~on_done:(fun events -> edit_menu ~rounds_dir ~source_dir ~path ~name ~events ())
            ()
      | 5 ->
        text_step
          ~label:"Round name"
          ~buffer:name
          ~on_back:(fun () -> back ())
          ~on_submit:(fun new_name ->
            let new_name = String.strip new_name in
            let new_name = if String.is_empty new_name then name else new_name in
            edit_menu ~rounds_dir ~source_dir ~path ~name:new_name ~events ())
          ()
      | 6 -> save_round ~rounds_dir ~source_dir ~name ~events ~output_path:(Some path) ~on_cancel:back
      | _ -> discard_confirm ())
    ()

and ask_event_index ~events ~prompt ~on_index ~cancel ?error () =
  if List.is_empty events
  then message ~text:[ "No events yet." ] ~next:(cancel ())
  else
    text_step
      ~label:(sprintf "%s (1-%d)" prompt (List.length events))
      ?error
      ~on_back:(fun () -> cancel ())
      ~on_submit:(fun s ->
        match parse_int s with
        | Some n when n >= 1 && n <= List.length events -> on_index (n - 1)
        | _ -> ask_event_index ~events ~prompt ~on_index ~cancel ~error:"Enter a valid event number" ())
      ()

and edit_event ~rounds_dir ~source_dir ~path ~name ~events ~idx () =
  let before = List.take events idx in
  let after = List.drop events (idx + 1) in
  let existing = List.nth_exn events idx in
  let rebuild event =
    edit_menu ~rounds_dir ~source_dir ~path ~name ~events:(before @ [ event ] @ after) ()
  in
  let cancel () = edit_menu ~rounds_dir ~source_dir ~path ~name ~events () in
  match existing with
  | Round.Event.Break { duration } ->
    ask_break_duration
      ~cancel
      ~on_break:(fun duration -> rebuild (Round.Event.Break { duration }))
      ~buffer:(Int.to_string duration)
      ()
  | Round.Event.Song { song; _ } ->
    ask_song_duration ~filepath:song.filepath ~on_song:rebuild ~cancel ~buffer:(Int.to_string song.duration) ()
;;

let apply_action (_context : _ Bonsai.Apply_action_context.t) (model : Model.t) (key : Event.Key.t)
  : Model.t
  =
  match model, key with
  | Model.Text ts, Event.Key.ASCII c ->
    Text { ts with t_buffer = ts.t_buffer ^ String.of_char c; t_error = None }
  | Text ts, Backspace ->
    Text
      { ts with
        t_buffer = (if String.is_empty ts.t_buffer then "" else String.drop_suffix ts.t_buffer 1)
      }
  | Text ts, Enter -> ts.t_on_submit ts.t_buffer
  | Text ts, Escape -> (match ts.t_on_back with Some f -> f () | None -> Text ts)
  | Path ps, Event.Key.ASCII c ->
    let buffer = ps.p_buffer ^ String.of_char c in
    Path
      { ps with
        p_buffer = buffer
      ; p_error = None
      ; p_suggestions = Dir_browser.path_completions buffer
      ; p_highlighted = 0
      }
  | Path ps, Backspace ->
    let buffer = if String.is_empty ps.p_buffer then "" else String.drop_suffix ps.p_buffer 1 in
    Path
      { ps with
        p_buffer = buffer
      ; p_suggestions = Dir_browser.path_completions buffer
      ; p_highlighted = 0
      }
  | Path ps, Tab ->
    (match List.nth ps.p_suggestions ps.p_highlighted with
     | None -> Path ps
     | Some buffer ->
       Path
         { ps with
           p_buffer = buffer
         ; p_suggestions = Dir_browser.path_completions buffer
         ; p_highlighted = 0
         })
  | Path ps, Arrow `Up -> Path { ps with p_highlighted = Int.max 0 (ps.p_highlighted - 1) }
  | Path ps, Arrow `Down ->
    Path { ps with p_highlighted = Int.min (List.length ps.p_suggestions - 1) (ps.p_highlighted + 1) }
  | Path ps, Enter -> ps.p_on_submit ps.p_buffer
  | Path ps, Escape -> (match ps.p_on_back with Some f -> f () | None -> Path ps)
  | Select ss, Arrow `Up -> Select { ss with s_selected = Int.max 0 (ss.s_selected - 1) }
  | Select ss, Arrow `Down ->
    Select { ss with s_selected = Int.min (List.length ss.s_items - 1) (ss.s_selected + 1) }
  | Select ss, Enter -> ss.s_on_select ss.s_selected
  | Select ss, Escape -> (match ss.s_on_back with Some f -> f () | None -> Select ss)
  | Filter_select fs, Event.Key.ASCII c ->
    Filter_select { fs with f_query = fs.f_query ^ String.of_char c; f_highlighted = 0 }
  | Filter_select fs, Backspace ->
    Filter_select
      { fs with
        f_query = (if String.is_empty fs.f_query then "" else String.drop_suffix fs.f_query 1)
      ; f_highlighted = 0
      }
  | Filter_select fs, Arrow `Up -> Filter_select { fs with f_highlighted = Int.max 0 (fs.f_highlighted - 1) }
  | Filter_select fs, Arrow `Down ->
    let n = List.length (filtered_items fs) in
    Filter_select { fs with f_highlighted = Int.min (n - 1) (fs.f_highlighted + 1) }
  | Filter_select fs, (Enter | Tab) ->
    (match List.nth (filtered_items fs) fs.f_highlighted with
     | Some item -> fs.f_on_select item
     | None -> Filter_select fs)
  | Filter_select fs, Escape -> (match fs.f_on_back with Some f -> f () | None -> Filter_select fs)
  | Message ms, _ -> ms.m_next
  | Confirm cs, ASCII ('y' | 'Y') -> cs.c_on_yes
  | Confirm cs, (ASCII ('n' | 'N') | Escape) -> cs.c_on_no
  | Reorder rs, Arrow `Up ->
    if rs.r_grabbed
    then (
      let moved = rs.r_cursor > 0 in
      Reorder
        { rs with
          r_events = swap_adjacent rs.r_events rs.r_cursor (rs.r_cursor - 1)
        ; r_cursor = (if moved then rs.r_cursor - 1 else rs.r_cursor)
        })
    else Reorder { rs with r_cursor = Int.max 0 (rs.r_cursor - 1) }
  | Reorder rs, Arrow `Down ->
    if rs.r_grabbed
    then (
      let moved = rs.r_cursor < List.length rs.r_events - 1 in
      Reorder
        { rs with
          r_events = swap_adjacent rs.r_events rs.r_cursor (rs.r_cursor + 1)
        ; r_cursor = (if moved then rs.r_cursor + 1 else rs.r_cursor)
        })
    else Reorder { rs with r_cursor = Int.min (List.length rs.r_events - 1) (rs.r_cursor + 1) }
  | Reorder rs, (Enter | ASCII ' ') -> Reorder { rs with r_grabbed = not rs.r_grabbed }
  | Reorder rs, Escape -> rs.r_on_done rs.r_events
  | Quit, _ -> Quit
  | _ -> model
;;

let footer parts = View.text (String.concat ~sep:"   " (parts @ [ "Ctrl+C quit" ]))

let window_indices ~total ~focus ~height =
  if total <= height
  then List.range 0 total
  else (
    let half = height / 2 in
    let start = Int.clamp_exn (focus - half) ~min:0 ~max:(Int.max 0 (total - height)) in
    List.range start (Int.min total (start + height)))
;;

let render_scroll_note ~total ~shown_start ~shown_end =
  if shown_start > 0 || shown_end < total
  then
    [ View.text
        ~attrs:[ Attr.italic ]
        (sprintf "(%d-%d of %d -- scroll with up/down)" (shown_start + 1) shown_end total)
    ]
  else []
;;

let render_text_step (ts : Model.text_step) =
  let info = List.map ts.t_info ~f:View.text in
  let error_view = match ts.t_error with None -> [] | Some e -> [ View.text e ] in
  let hints =
    List.filter_opt [ Some "Enter submit"; Option.map ts.t_on_back ~f:(fun _ -> "Esc back") ]
  in
  View.vcat
    (info
     @ [ View.text ~attrs:[ Attr.bold ] ts.t_label; View.text (ts.t_buffer ^ "_") ]
     @ error_view
     @ [ View.none; footer hints ])
;;

let render_path_step ~list_height (ps : Model.path_step) =
  let info = List.map ps.p_info ~f:View.text in
  let error_view = match ps.p_error with None -> [] | Some e -> [ View.text e ] in
  let indices = window_indices ~total:(List.length ps.p_suggestions) ~focus:ps.p_highlighted ~height:list_height in
  let suggestion_rows =
    List.map indices ~f:(fun i ->
      let s = List.nth_exn ps.p_suggestions i in
      if i = ps.p_highlighted then View.text ~attrs:[ Attr.invert ] s else View.text s)
  in
  let hints =
    List.filter_opt
      [ Some "Tab complete"
      ; (if List.is_empty ps.p_suggestions then None else Some "up/down pick suggestion")
      ; Some "Enter submit"
      ; Option.map ps.p_on_back ~f:(fun _ -> "Esc back")
      ]
  in
  View.vcat
    (info
     @ [ View.text ~attrs:[ Attr.bold ] ps.p_label; View.text (ps.p_buffer ^ "_") ]
     @ error_view
     @ [ View.none ]
     @ suggestion_rows
     @ [ View.none; footer hints ])
;;

let render_select_step ~list_height (ss : Model.select_step) =
  let title = List.map ss.s_title ~f:(fun l -> View.text ~attrs:[ Attr.bold ] l) in
  let indices = window_indices ~total:(List.length ss.s_items) ~focus:ss.s_selected ~height:list_height in
  let rows =
    List.map indices ~f:(fun i ->
      let item = List.nth_exn ss.s_items i in
      if i = ss.s_selected then View.text ~attrs:[ Attr.invert ] ("> " ^ item) else View.text ("  " ^ item))
  in
  let scroll_note =
    match indices with
    | [] -> []
    | _ ->
      render_scroll_note
        ~total:(List.length ss.s_items)
        ~shown_start:(List.hd_exn indices)
        ~shown_end:(List.last_exn indices + 1)
  in
  let hints =
    List.filter_opt
      [ Some "up/down move"; Some "Enter select"; Option.map ss.s_on_back ~f:(fun _ -> "Esc back") ]
  in
  View.vcat (title @ [ View.none ] @ rows @ scroll_note @ [ View.none; footer hints ])
;;

let render_filter_select_step ~list_height (fs : Model.filter_select_step) =
  let title = List.map fs.f_title ~f:(fun l -> View.text ~attrs:[ Attr.bold ] l) in
  let items = filtered_items fs in
  let search_line = View.text (sprintf "Search: %s_" fs.f_query) in
  let indices = window_indices ~total:(List.length items) ~focus:fs.f_highlighted ~height:list_height in
  let rows =
    if List.is_empty items
    then [ View.text "(no matches)" ]
    else
      List.map indices ~f:(fun i ->
        let item = List.nth_exn items i in
        if i = fs.f_highlighted
        then View.text ~attrs:[ Attr.invert ] ("> " ^ item)
        else View.text ("  " ^ item))
  in
  let scroll_note =
    match indices with
    | [] -> []
    | _ ->
      render_scroll_note
        ~total:(List.length items)
        ~shown_start:(List.hd_exn indices)
        ~shown_end:(List.last_exn indices + 1)
  in
  let hints =
    List.filter_opt
      [ Some "Type to search"
      ; Some "up/down move"
      ; Some "Enter/Tab select"
      ; Option.map fs.f_on_back ~f:(fun _ -> "Esc back")
      ]
  in
  View.vcat (title @ [ search_line; View.none ] @ rows @ scroll_note @ [ View.none; footer hints ])
;;

let render_message (ms : Model.message_step) =
  let lines = List.map ms.m_text ~f:View.text in
  View.vcat (lines @ [ View.none; footer [ "press any key to continue" ] ])
;;

let render_confirm (cs : Model.confirm_step) =
  View.vcat [ View.text cs.c_prompt; View.none; footer [ "y yes"; "n no" ] ]
;;

let render_reorder_step ~list_height (rs : Model.reorder_step) =
  let total = List.length rs.r_events in
  let indices = window_indices ~total ~focus:rs.r_cursor ~height:list_height in
  let rows =
    List.map indices ~f:(fun i ->
      let ev = List.nth_exn rs.r_events i in
      let label = sprintf "%d. %s" (i + 1) (Round.Event.to_string ev) in
      if i = rs.r_cursor
      then
        if rs.r_grabbed
        then View.text ~attrs:[ Attr.invert; Attr.bold ] ("* " ^ label ^ " *")
        else View.text ~attrs:[ Attr.invert ] ("> " ^ label)
      else View.text ("  " ^ label))
  in
  let scroll_note =
    match indices with
    | [] -> []
    | _ ->
      render_scroll_note ~total ~shown_start:(List.hd_exn indices) ~shown_end:(List.last_exn indices + 1)
  in
  let hints =
    if rs.r_grabbed
    then [ "up/down move item"; "Enter/Space drop"; "Esc done" ]
    else [ "up/down move cursor"; "Enter/Space grab"; "Esc done" ]
  in
  View.vcat
    ([ View.text ~attrs:[ Attr.bold ] "Reorder events"; View.none ]
     @ rows
     @ scroll_note
     @ [ View.none; footer hints ])
;;

let view_of_model ~list_height : Model.t -> View.t = function
  | Text ts -> render_text_step ts
  | Path ps -> render_path_step ~list_height ps
  | Select ss -> render_select_step ~list_height ss
  | Filter_select fs -> render_filter_select_step ~list_height fs
  | Message ms -> render_message ms
  | Confirm cs -> render_confirm cs
  | Reorder rs -> render_reorder_step ~list_height rs
  | Quit -> View.text "Bye!"
;;

let app ~exit ~(dimensions : Dimensions.t Bonsai.t) (local_ graph)
  : view:View.t Bonsai.t * handler:(Event.t -> unit Effect.t) Bonsai.t
  =
  let model, inject = Bonsai.state_machine ~default_model:(ask_rounds_dir ()) ~apply_action graph in
  let view =
    let%arr model and dimensions in
    let list_height = Int.max 3 (dimensions.Dimensions.height - 8) in
    View.pad ~l:2 ~t:1 (view_of_model ~list_height model)
  in
  let handler =
    let%arr inject and model in
    fun (event : Event.t) ->
      match event with
      | Key_press { key = ASCII c; mods }
        when Char.equal (Char.uppercase c) 'C'
             && List.mem mods Event.Modifier.Ctrl ~equal:Event.Modifier.equal -> exit ()
      | Key_press { key; _ } ->
        (match model with
         | Model.Quit -> exit ()
         | _ -> inject key)
      | _ -> Effect.Ignore
  in
  ~view, ~handler
;;

let command =
  Command.async_or_error
    ~summary:"Interactive rounds editor"
    (let%map_open.Command () = return () in
     fun () -> Bonsai_term.start_with_exit app)
;;
