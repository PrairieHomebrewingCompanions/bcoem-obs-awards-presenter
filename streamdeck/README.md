# Stream Deck + plugin

Two dial actions that follow the show in the BCOE&M Awards Presenter app:

| Dial | Touch strip | Turn | Press |
| --- | --- | --- | --- |
| **Live Category** | the table on screen, and which places are showing (lit = shown) | — | hide all places |
| **Next Category** | the table on standby, and where it is in the list | choose the next table | GO |

Turning only moves standby, so a bumped dial can't change what's on screen.
The strips show **Offline** when the app isn't running and say so when the
app has lost OBS. A dial shakes (Stream Deck's alert) when a command fails,
e.g. GO with OBS disconnected; the reason is in the plugin's log.

It's plain JavaScript with no dependencies or build step. Stream Deck runs it
on its own Node.js, so Node doesn't need to be installed.

## Installing

The plugin is for the Stream Deck app on macOS. From this repository's
folder, link the plugin into Stream Deck, then quit and reopen the Stream
Deck app:

    ln -s "$PWD/streamdeck/io.github.prairiehomebrewingcompanions.bcoem-obs-awards-presenter.sdPlugin" \
      ~/Library/Application\ Support/com.elgato.StreamDeck/Plugins/

The actions appear under **BCOE&M Awards Presenter** in the action list.
Drag **Live Category** and **Next Category** onto two dials.

Because it's a link, edits here take effect the next time Stream Deck restarts
the plugin (quit and reopen the app).

## Details

- The app's address is `APP_URL` at the top of `plugin.js`
  (`ws://127.0.0.1:4000/api/deck`). The socket is `BcoemObsAwardsPresenterWeb.DeckSocket`.
- Logs: `~/Library/Logs/ElgatoStreamDeck/io.github.prairiehomebrewingcompanions.bcoem-obs-awards-presenter0.log`
- `layouts/` holds the touch strip layouts (200×100 per dial). The images in
  `imgs/` come from `tools/draw-images.exs`, a standalone Elixir script
  (usage at the top of the file).
