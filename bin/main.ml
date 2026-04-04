open Ballroom_rounds_maker_lib.File_utils
open Ballroom_rounds_maker_lib.Generate_artifacts

[@@@warning "-32"]
[@@@warning "-26"]

let smooth_champ =
  [ "Smooth/AmWaltz/Infinity (Slow Waltz 29).mp3"
  ; "<BREAK> 10"
  ; "Smooth/AmTango/Alè Maria.mp3"
  ; "<BREAK> 10"
  ; "Smooth/AmFox/It Serve You Right To Suffer - The Avener Rework_spotdown.org.mp3"
  ; "<BREAK> 10"
  ; "Smooth/AmVWaltz/Lose Control_spotdown.org.mp3"
  ]

let standard_champ_2heats =
  [ "Standard/Waltz/Way Over Yonder_spotdown.org.mp3"
  ; "<BREAK> 5"
  ; "Standard/Waltz/Way Over Yonder_spotdown.org.mp3"
  ; "<BREAK> 10"
  ; "Standard/Tango/Tango city_spotdown.org.mp3"
  ; "<BREAK> 5"
  ; "Standard/Tango/Stateside + Zara Larsson_spotdown.org.mp3"
  ; "<BREAK> 10"
  ; "Standard/VWaltz/To Dust_spotdown.org.mp3"
  ; "<BREAK> 5"
  ; {|Standard/VWaltz/Circle Of Life_spotdown.org.mp3|}
  ; "<BREAK> 10"
  ; "Standard/Fox/Swing Supreme_spotdown.org.mp3"
  ; "<BREAK> 5"
  ; "Standard/Fox/Swing Supreme_spotdown.org.mp3"
  ; "<BREAK> 10"
  ; {|Standard/Quickstep/晴る_spotdown.org.mp3|}
  ; "<BREAK> 5"
  ; {|Standard/Quickstep/Пляшем я и Маша.mp3|}
  ]

let standard_champ_1heat =
  [ "Standard/Waltz/Don't Be So Shy (Slow Watlz 29)_spotdown.org.mp3"
  ; "<BREAK> 10"
  ; "Standard/Tango/The Punch and Judy Tango (Tango)_spotdown.org.mp3"
  ; "<BREAK> 10"
  ; "Standard/VWaltz/Love Story - Indila.mp3"
  ; "<BREAK> 10"
  ; "Standard/Fox/Better Together_spotdown.org.mp3"
  ; "<BREAK> 10"
  ; "Standard/Quickstep/Larger Than Life (feat. Benji Jackson)_spotdown.org.mp3"
  ]

let standard_gold_2heats =
  [ "Standard/Waltz/Way Over Yonder_spotdown.org.mp3"
  ; "<BREAK> 5"
  ; "Standard/Waltz/Way Over Yonder_spotdown.org.mp3"
  ; "<BREAK> 10"
  ; "Standard/Tango/Tango city_spotdown.org.mp3"
  ; "<BREAK> 5"
  ; "Standard/Tango/Stateside + Zara Larsson_spotdown.org.mp3"
  ; "<BREAK> 10"
  ; "Standard/Fox/Swing Supreme_spotdown.org.mp3"
  ; "<BREAK> 5"
  ; "Standard/Fox/Swing Supreme_spotdown.org.mp3"
  ; "<BREAK> 10"
  ; {|Standard/Quickstep/晴る_spotdown.org.mp3|}
  ; "<BREAK> 5"
  ; {|Standard/Quickstep/Пляшем я и Маша.mp3|}
  ]

let rhythm_champ =
  [ "Rhythm/AmCha/Mystical Magical_spotdown.org.mp3"
  ; "<BREAK> 10"
  ; "Rhythm/AmRumba/I Am Better Off_spotdown.org.mp3"
  ; "<BREAK> 10"
  ; "Rhythm/Swing/I Want It_spotdown.org.mp3"
  ; "<BREAK> 10"
  ; "Rhythm/Bolero/Risk It All_spotdown.org.mp3"
  ; "<BREAK> 10"
  ; "Rhythm/Mambo/Tiahuanaco (Puerta Del Sol)_spotdown.org.mp3"
  ]

let latin_champ_2heats =
  [ "Latin/Cha/Undress Rehearsal.mp3"
  ; "<BREAK> 5"
  ; "Latin/Cha/Sax [ChaChaCha - 31BPM].mp3"
  ; "<BREAK> 10"
  ; "Latin/Samba/Con Calma.mp3"
  ; "<BREAK> 5"
  ; "Latin/Samba/No Lie.mp3"
  ; "<BREAK> 10"
  ; "Latin/Rumba/Love Yourself.mp3"
  ; "<BREAK> 5"
  ; "Latin/Rumba/Love Yourself.mp3"
  ; "<BREAK> 10"
  ; "Latin/Paso/Titanic Theme.mp3"
  ; "<BREAK> 5"
  ; "Latin/Paso/Titanic Theme.mp3"
  ; "<BREAK> 10"
  ; "Latin/Jive/It Is What It Is.mp3"
  ; "<BREAK> 5"
  ; "Latin/Jive/It Is What It Is.mp3"
  ]

let latin_gold_2heats =
  [ "Latin/Cha/Undress Rehearsal.mp3"
  ; "<BREAK> 5"
  ; "Latin/Cha/Sax [ChaChaCha - 31BPM].mp3"
  ; "<BREAK> 10"
  ; "Latin/Samba/Con Calma.mp3"
  ; "<BREAK> 5"
  ; "Latin/Samba/No Lie.mp3"
  ; "<BREAK> 10"
  ; "Latin/Rumba/Love Yourself.mp3"
  ; "<BREAK> 5"
  ; "Latin/Rumba/Love Yourself.mp3"
  ; "<BREAK> 10"
  ; "Latin/Jive/It Is What It Is.mp3"
  ; "<BREAK> 5"
  ; "Latin/Jive/It Is What It Is.mp3"
  ]

let latin_champ_1heat =
  [ "Latin/Cha/Undress Rehearsal.mp3"
  ; "<BREAK> 10"
  ; "Latin/Samba/Con Calma.mp3"
  ; "<BREAK> 10"
  ; "Latin/Rumba/Love Yourself.mp3"
  ; "<BREAK> 10"
  ; "Latin/Paso/Espana Cani '2013' - Paso Doble _ 61 BPM_spotdown.org.mp3"
  ; "<BREAK> 10"
  ; "Latin/Jive/It Is What It Is.mp3"
  ]

let solo_paso =
  [ "Latin/Paso/Titanic Theme.mp3" ]

let create_hell_rounds (events : string list)
    (output_name : string) : unit =
  let source_directory = "hellrounds_source" in
  let artifacts_directory = "hellrounds_source_artifacts" in

  (* Trim all songs *)
  let events: artifact list = List.map (create_artifact ~ffmpeg_path:"./ffmpeg" source_directory artifacts_directory) events in
  let trimmed_events = List.map trim_artifact events in
  concat_artifacts ~ffmpeg_path:"./ffmpeg" artifacts_directory trimmed_events output_name

let () =
  if check_event_files_exist "hellrounds_source" smooth_champ then
    print_endline "All events files exist"
  else
    print_endline "Some events files do not exist";
  (* create_hell_rounds "hellrounds_source" latin_champ_2heats "latin_champ_2heats.mp3"; *)
  (* create_hell_rounds "hellrounds_source" latin_champ_1heat "latin_champ_1heat.mp3"; *)
  (* create_hell_rounds "hellrounds_source" solo_paso "solo_paso.mp3"; *)
  (* create_hell_rounds "hellrounds_source" latin_gold_2heats "latin_gold_2heats.mp3"; *)
  create_hell_rounds standard_champ_1heat "standard_champ_1heat.mp3"
  (* create_hell_rounds "hellrounds_source" standard_gold_2heats "standard_gold_2heats.mp3"; *)
  (* create_hell_rounds "hellrounds_source" standard_champ_2heats "standard_champ_2heats.mp3"; *)
  (* create_hell_rounds "hellrounds_source" smooth_champ "smooth_champ.mp3"; *)
  (* create_hell_rounds "hellrounds_source" rhythm_champ "rhythm_champ.mp3"; *)
