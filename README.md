# bcoem-obs-awards-presenter

Present a homebrew competition's results live in OBS, straight from
[BCOE&M](https://brewcompetition.com) (Brew Competition Online Entry &
Management).

Drop BCOE&M's winners export on a control page in your browser, and it
becomes a cue list with one row per table. Each **GO** puts the next
category's placings (brewer, entry, club and style for 1st, 2nd and 3rd)
into text sources in OBS, ready for you to reveal 3rd → 2nd → 1st. It works
like a theatre cue list (in the spirit of QLab), so the person running the
stream only ever presses GO.

- Runs from the keyboard (Space for GO), from Stream Deck buttons, or from a
  Stream Deck + plugin whose dials show the live and next categories.
- Can create the OBS scene and text sources it needs, ready to style.
- Keeps its place when you re-download a corrected export.

It runs on your own computer, alongside OBS: there are no accounts, and only
that computer can reach it.

## Running it

You need [Elixir](https://elixir-lang.org/install.html) 1.17 or newer (with
Erlang/OTP), and OBS 28 or newer, which has obs-websocket built in.

```sh
git clone <this repository> bcoem-obs-awards-presenter
cd bcoem-obs-awards-presenter
mix setup        # the first time only
mix phx.server
```

Then open http://localhost:4000 (set `PORT` to use another port).

The first time, open **OBS connection, setup and Stream Deck** at the bottom
of the page (it opens by itself while OBS is disconnected). Enter the address
and password from OBS → Tools → WebSocket Server Settings → Show Connect Info,
and click **Save and reconnect**. They're saved in your user settings folder
(`~/Library/Application Support/bcoem_obs_awards_presenter/` on a Mac,
`~/.config/bcoem_obs_awards_presenter/` on Linux,
`%APPDATA%\bcoem_obs_awards_presenter\` on Windows), outside the app's
folder.

## The winners export

1. Once every table's places are entered in BCOE&M, open the **Admin
   Dashboard** → **Data Exports** → **Participant Data (CSV)** →
   **Winners: Limited Data**. It downloads a CSV.
2. Drag the file onto the control page (anywhere on it), or click the box at
   the top and choose it. The cue list fills with one row per table, in table
   order.

Fixed a result in BCOE&M? Download the export again and drop it on the page:
the show keeps its place, even if the browser named it `… (1).csv`.

- The app uses Table, Name, Place, First Name, Last Name, Entry Name, Club,
  Style and Co-Brewer, and ignores the rest. Table names like
  "Table 31 - Fresh Hop Beers" show as "Fresh Hop Beers". Only 1st to 3rd
  are shown; honourable mentions are skipped.
- Best of Show isn't in this export, so make those slides in OBS.
- **The export includes winners' email addresses, home addresses and phone
  numbers.** The app keeps its one copy of the upload in the system's temp
  folder; keep the file itself off shared folders.

## Running the show

- **GO** (Space, or a Stream Deck button): hides all three places, loads the
  standby category into OBS, and moves standby to the next category.
- **Click any row**, or use ↑/↓, to put a different category on standby.
- **Esc** / **Hide all**: hides every place.
- A second GO within 750 ms is ignored, so a double-tapped button can't skip
  a category.

Reveal each place by showing its group in OBS (below), from a Stream Deck
OBS button, a hotkey or by clicking.

## OBS layout

The app fills these in. The names are set in `config/config.exs`:

```
Awards Overlay        (scene: add it as a source in each camera scene)
├── Award Category    (text)
├── Award 3rd         (scene, nested: show it to reveal 3rd place)
│   ├── Award 3rd Brewer / Entry / Club / Style   (text)
├── Award 2nd         (same)
└── Award 1st         (same)
```

**OBS connection, setup and Stream Deck** at the bottom of the control page
checks for these and can create any that are missing, with placeholder text
ready to style.

## Stream Deck

Any Stream Deck can run the show with the **Website** action, with **GET
request in background** ticked:

- `http://localhost:4000/api/go`
- `http://localhost:4000/api/next` / `api/prev`: move standby
- `http://localhost:4000/api/hide-all`

Use OBS buttons (from Stream Deck's OBS plugin) to reveal places: toggle
`Award 3rd`, `Award 2nd` and `Award 1st` in the `Awards Overlay` scene.

On a **Stream Deck +**, the plugin in [`streamdeck/`](streamdeck/README.md)
adds two dials whose touch strips show the live and next categories: turn to
choose the next one, press for GO.

## Developing

```sh
mix test         # the tests
mix precommit    # compile warnings, formatting and tests, before committing
```

It's a [Phoenix LiveView](https://www.phoenixframework.org) app with no
database. `AGENTS.md` has the project's coding guidelines.

## See also

[obs-slideshow-overlay](https://github.com/PrairieHomebrewingCompanions/obs-slideshow-overlay)
makes the slideshows to show between categories: sponsors, thank-yous and
photos.

## License

[MIT](LICENSE)
