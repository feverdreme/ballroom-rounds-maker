%{
  open Generate_artifacts

  let build_defaults (settings : (string * int) list) : defaults =
    let d = ref default_defaults in
    List.iter (fun (key, value) ->
      match key with
      | "song_duration"  -> d := { !d with song_duration = value }
      | "break_duration" -> d := { !d with break_duration = value }
      | "fade_in"        -> d := { !d with fade_in = value }
      | "fade_out"       -> d := { !d with fade_out = value }
      | _ -> invalid_arg (Printf.sprintf "Unknown default setting: %s" key)
    ) settings;
    !d

  let build_config (options : (string * int) list) : song_config =
    let c = ref empty_config in
    List.iter (fun (key, value) ->
      match key with
      | "start"    -> c := { !c with start = Some value }
      | "end"      -> c := { !c with end_at = Some value }
      | "duration" -> c := { !c with duration = Some value }
      | "fade_in"  -> c := { !c with fade_in = Some value }
      | "fade_out" -> c := { !c with fade_out = Some value }
      | _ -> invalid_arg (Printf.sprintf "Unknown song option: %s" key)
    ) options;
    !c
%}

%token LBRACKET RBRACKET DEFAULTS ROUND BREAK EQUALS PIPE NEWLINE EOF
%token <int> INT
%token <string> IDENT
%token <string> PATH

%start <Generate_artifacts.rounds_file> rounds_file

%%

rounds_file:
  | newlines; d = defaults_section?; rounds = round_section*; EOF
    { { defaults = (match d with Some d -> d | None -> default_defaults);
        rounds } }

defaults_section:
  | LBRACKET; DEFAULTS; RBRACKET; newlines; settings = setting*
    { build_defaults settings }

setting:
  | key = IDENT; EQUALS; value = INT; newlines
    { (key, value) }

round_section:
  | LBRACKET; ROUND; name = IDENT; RBRACKET; newlines; entries = entry*
    { { name; entries } }

entry:
  | BREAK; newlines
    { Break { path = ""; duration = 0 } }
  | BREAK; duration = INT; newlines
    { Break { path = ""; duration } }
  | path = PATH; options = song_option*; newlines
    { Song { path; config = build_config options } }

song_option:
  | PIPE; key = IDENT; EQUALS; value = INT
    { (key, value) }

newlines:
  | NEWLINE* { () }
