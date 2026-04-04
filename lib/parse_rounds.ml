(** Line-by-line tokenizer that feeds tokens to the menhir parser.
    Handles context-sensitive lexing: file paths (which contain spaces, parens, brackets)
    are only recognized inside [round] sections. *)

type mode = Toplevel | InDefaults | InRound

let tokenize_contents (contents : string) : Parser.token list =
  let tokens = ref [] in
  let emit t = tokens := t :: !tokens in
  let mode = ref Toplevel in
  let lines = String.split_on_char '\n' contents in
  List.iter (fun raw_line ->
    let line = String.trim raw_line in
    if line = "" || (String.length line > 0 && (line.[0] = '#' || line.[0] = ';')) then
      emit Parser.NEWLINE
    else if String.length line >= 2 && line.[0] = '[' then begin
      let close = String.index line ']' in
      let inner = String.trim (String.sub line 1 (close - 1)) in
      emit Parser.LBRACKET;
      if inner = "defaults" then begin
        mode := InDefaults;
        emit Parser.DEFAULTS
      end else if String.starts_with ~prefix:"round " inner then begin
        mode := InRound;
        emit Parser.ROUND;
        let name = String.trim (String.sub inner 6 (String.length inner - 6)) in
        emit (Parser.IDENT name)
      end else
        invalid_arg (Printf.sprintf "Unknown section: [%s]" inner);
      emit Parser.RBRACKET;
      emit Parser.NEWLINE
    end else match !mode with
    | Toplevel ->
      invalid_arg (Printf.sprintf "Unexpected content outside section: %s" line)
    | InDefaults ->
      (match String.split_on_char '=' line with
       | [key; value] ->
         emit (Parser.IDENT (String.trim key));
         emit Parser.EQUALS;
         emit (Parser.INT (int_of_string (String.trim value)));
         emit Parser.NEWLINE
       | _ -> invalid_arg (Printf.sprintf "Malformed setting: %s" line))
    | InRound ->
      let is_break =
        String.starts_with ~prefix:"break" line
        && (String.length line = 5 || line.[5] = ' ' || line.[5] = '\t')
      in
      if is_break then begin
        emit Parser.BREAK;
        let rest = String.trim (
          if String.length line > 5 then String.sub line 5 (String.length line - 5)
          else ""
        ) in
        if rest <> "" then
          emit (Parser.INT (int_of_string rest));
        emit Parser.NEWLINE
      end else begin
        let parts = String.split_on_char '|' line in
        (match parts with
         | [] -> emit Parser.NEWLINE
         | path :: options ->
           emit (Parser.PATH (String.trim path));
           List.iter (fun opt ->
             let opt = String.trim opt in
             (match String.split_on_char '=' opt with
              | [key; value] ->
                emit Parser.PIPE;
                emit (Parser.IDENT (String.trim key));
                emit Parser.EQUALS;
                emit (Parser.INT (int_of_string (String.trim value)))
              | _ -> invalid_arg (Printf.sprintf "Malformed song option: %s" opt))
           ) options;
           emit Parser.NEWLINE)
      end
  ) lines;
  emit Parser.EOF;
  List.rev !tokens

let parse_string (contents : string) : Generate_artifacts.rounds_file =
  let tokens = tokenize_contents contents in
  let tokens_ref = ref tokens in
  let tokenizer _lexbuf =
    match !tokens_ref with
    | [] -> Parser.EOF
    | t :: rest -> tokens_ref := rest; t
  in
  let dummy_lexbuf = Lexing.from_string "" in
  Parser.rounds_file tokenizer dummy_lexbuf

let parse_file (filename : string) : Generate_artifacts.rounds_file =
  let ic = open_in filename in
  let contents = Fun.protect ~finally:(fun () -> close_in ic) (fun () ->
    In_channel.input_all ic
  ) in
  parse_string contents
