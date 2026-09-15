let index_html =
  {|<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="color-scheme" content="light">
    <title>Ballroom Rounds Maker</title>
    <link rel="stylesheet" href="/app.css">
  </head>
  <body>
    <div id="app"><div class="boot">Opening the rounds editor…</div></div>
    <script src="/app.js"></script>
  </body>
</html>|}
;;

let stylesheet =
  {|:root {
  --ink: #202523;
  --muted: #67706b;
  --paper: #f6f2e9;
  --panel: #fffdf8;
  --line: #d9d2c5;
  --accent: #8e352f;
  --accent-dark: #67231f;
  --green: #315d4c;
  font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  color: var(--ink);
  background: var(--paper);
}
* { box-sizing: border-box; }
body { margin: 0; min-width: 320px; background: radial-gradient(circle at top right, #efe0cc 0, transparent 35rem), var(--paper); }
button, input, select { font: inherit; }
button { cursor: pointer; }
.boot { padding: 4rem; text-align: center; color: var(--muted); }
.shell { max-width: 1120px; margin: 0 auto; padding: 32px 24px 64px; }
.masthead { display: flex; justify-content: space-between; align-items: flex-end; gap: 24px; margin-bottom: 28px; }
.eyebrow { color: var(--accent); text-transform: uppercase; letter-spacing: .14em; font-weight: 800; font-size: 12px; }
h1, h2, h3, p { margin-top: 0; }
h1 { margin-bottom: 4px; font-family: Georgia, serif; font-size: clamp(32px, 5vw, 54px); line-height: 1; }
h2 { font-family: Georgia, serif; font-size: 28px; margin-bottom: 8px; }
.subtitle, .muted { color: var(--muted); }
.panel { background: color-mix(in srgb, var(--panel) 96%, transparent); border: 1px solid var(--line); border-radius: 16px; padding: 24px; box-shadow: 0 16px 40px rgba(55, 43, 31, .08); }
.workspace { max-width: 720px; margin: 7vh auto 0; }
.field { display: grid; gap: 7px; margin: 16px 0; }
.field label { font-weight: 700; font-size: 14px; }
input, select { width: 100%; border: 1px solid #bbb3a6; border-radius: 9px; padding: 11px 12px; background: white; color: var(--ink); }
input:focus, select:focus { outline: 3px solid rgba(142,53,47,.14); border-color: var(--accent); }
.actions { display: flex; flex-wrap: wrap; gap: 10px; align-items: center; }
.button { border: 1px solid var(--line); border-radius: 9px; padding: 10px 14px; background: white; color: var(--ink); font-weight: 700; }
.button:hover { border-color: #a99f90; background: #faf7f0; }
.button.primary { background: var(--accent); border-color: var(--accent); color: white; }
.button.primary:hover { background: var(--accent-dark); }
.button.danger { color: #9a2923; }
.button.icon { min-width: 38px; padding: 8px; }
.button:disabled { opacity: .45; cursor: default; }
.error { color: #9a2923; background: #fff0ed; border: 1px solid #edc1bb; border-radius: 9px; padding: 10px 12px; margin: 12px 0; }
.success { color: var(--green); font-weight: 700; }
.toolbar { display: flex; justify-content: space-between; align-items: center; gap: 16px; margin-bottom: 18px; }
.round-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(235px, 1fr)); gap: 14px; }
.round-card { text-align: left; border: 1px solid var(--line); border-radius: 12px; padding: 18px; background: white; min-height: 112px; }
.round-card:hover { border-color: var(--accent); transform: translateY(-1px); }
.round-card strong { display: block; margin-bottom: 8px; font-family: Georgia, serif; font-size: 20px; }
.editor-grid { display: grid; grid-template-columns: minmax(0, 1fr) 300px; gap: 20px; align-items: start; }
.event-list { display: grid; gap: 10px; margin: 18px 0; }
.event { display: grid; grid-template-columns: 42px minmax(0, 1fr) auto; gap: 12px; align-items: center; padding: 14px; background: white; border: 1px solid var(--line); border-radius: 12px; }
.event-index { display: grid; place-items: center; width: 34px; height: 34px; border-radius: 50%; background: #eee7dc; font-weight: 800; }
.event-title { font-weight: 800; overflow-wrap: anywhere; }
.event-meta { color: var(--muted); font-size: 13px; margin-top: 4px; }
.event-actions { display: flex; gap: 6px; }
.empty { padding: 40px 16px; border: 1px dashed #bdb4a6; border-radius: 12px; text-align: center; color: var(--muted); }
.sidebar { position: sticky; top: 20px; }
.status { min-height: 24px; color: var(--muted); font-size: 14px; }
.dialog-backdrop { position: fixed; inset: 0; display: grid; place-items: center; padding: 20px; background: rgba(28,27,25,.55); z-index: 10; }
.dialog { width: min(600px, 100%); max-height: 90vh; overflow: auto; background: var(--panel); border-radius: 16px; padding: 24px; box-shadow: 0 24px 80px rgba(0,0,0,.26); }
.search-results { max-height: 240px; overflow: auto; border: 1px solid var(--line); border-radius: 9px; background: white; }
.song-choice { width: 100%; border: 0; border-bottom: 1px solid #eee8df; background: white; padding: 10px 12px; text-align: left; overflow-wrap: anywhere; }
.song-choice:hover, .song-choice.selected { background: #f4ece2; }
@media (max-width: 760px) {
  .shell { padding: 22px 14px 48px; }
  .masthead, .toolbar { align-items: stretch; flex-direction: column; }
  .editor-grid { grid-template-columns: 1fr; }
  .sidebar { position: static; }
  .event { grid-template-columns: 36px minmax(0, 1fr); }
  .event-actions { grid-column: 1 / -1; }
}|}
;;
