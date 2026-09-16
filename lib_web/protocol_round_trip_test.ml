open! Core
module Protocol = Rounds_web_protocol.Protocol
module Round = Rounds_model.Round

let assert_round_trip ~sexp_of ~of_sexp value =
  let encoded = sexp_of value in
  let decoded = of_sexp encoded in
  let reencoded = sexp_of decoded in
  assert (Sexp.equal encoded reencoded)
;;

let sample_round =
  let song =
    Round.Song.create
      ~filepath:"Standard/Waltz/example.mp3"
      ~duration:90
      ~fade_in:3
      ~fade_out:5
    |> Or_error.ok_exn
  in
  { Round.name = "Evening round"
  ; events =
      [ Song { song_data = song; name = Some "Opening Waltz"; dance = Some "Waltz" }
      ; Break { duration = 12 }
      ]
  }
;;

let () =
  assert_round_trip ~sexp_of:Round.sexp_of_t ~of_sexp:Round.t_of_sexp sample_round;
  let workspace = Protocol.{ rounds_dir = "rounds"; source_dir = "music" } in
  assert_round_trip
    ~sexp_of:Protocol.sexp_of_workspace
    ~of_sexp:Protocol.workspace_of_sexp
    workspace;
  let initialize_result =
    Protocol.
      { rounds = [ { path = "evening.sexp"; name = "Evening round"; event_count = 2 } ]
      ; songs = [ "Standard/Waltz/example.mp3" ]
      }
  in
  assert_round_trip
    ~sexp_of:Protocol.sexp_of_initialize_result
    ~of_sexp:Protocol.initialize_result_of_sexp
    initialize_result;
  assert_round_trip
    ~sexp_of:Protocol.sexp_of_list_rounds_request
    ~of_sexp:Protocol.list_rounds_request_of_sexp
    workspace;
  assert_round_trip
    ~sexp_of:Protocol.sexp_of_list_rounds_result
    ~of_sexp:Protocol.list_rounds_result_of_sexp
    initialize_result.rounds;
  assert_round_trip
    ~sexp_of:Protocol.sexp_of_list_songs_request
    ~of_sexp:Protocol.list_songs_request_of_sexp
    workspace;
  assert_round_trip
    ~sexp_of:Protocol.sexp_of_list_songs_result
    ~of_sexp:Protocol.list_songs_result_of_sexp
    initialize_result.songs;
  assert_round_trip
    ~sexp_of:Protocol.sexp_of_load_request
    ~of_sexp:Protocol.load_request_of_sexp
    Protocol.{ workspace; path = "evening.sexp" };
  assert_round_trip
    ~sexp_of:Protocol.sexp_of_save_request
    ~of_sexp:Protocol.save_request_of_sexp
    Protocol.{ workspace; path = Some "evening.sexp"; round = sample_round };
  assert_round_trip
    ~sexp_of:(Or_error.sexp_of_t Protocol.sexp_of_save_result)
    ~of_sexp:(Or_error.t_of_sexp Protocol.save_result_of_sexp)
    (Ok { Protocol.path = "evening.sexp" })
;;
