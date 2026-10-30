// BCOE&M Awards Presenter for the Stream Deck +: two dial actions that follow the show
// running in the BCOE&M Awards Presenter app.
//
//   Live: the category on screen and which places are showing.
//         Press to hide all places.
//   Next: the category on standby. Turn to choose it, press to GO.
//
// The app pushes a summary of the show over /api/deck whenever it changes (see
// BcoemObsAwardsPresenterWeb.DeckSocket) and takes the same commands as its control page.
// This talks the Stream Deck's plugin protocol directly, with Node's built-in
// WebSocket, so there's nothing to install or build.

const APP_URL = "ws://127.0.0.1:4000/api/deck";
const LIVE = "io.github.prairiehomebrewingcompanions.bcoem-obs-awards-presenter.live";
const NEXT = "io.github.prairiehomebrewingcompanions.bcoem-obs-awards-presenter.next";

// The Stream Deck starts plugins with: -port N -pluginUUID U -registerEvent E -info JSON
const args = {};
for (let i = 2; i < process.argv.length; i += 2) {
  args[process.argv[i].replace(/^-/, "")] = process.argv[i + 1];
}

const dials = new Map(); // context -> action UUID, for every dial showing one of ours
let show = null; // the app's latest summary; null while the app is unreachable
let app = null;
let sender = null; // the dial behind the last command, to flag it if the command fails

const deck = new WebSocket(`ws://127.0.0.1:${args.port}`);
const toDeck = (event, context, payload) => deck.send(JSON.stringify({ event, context, payload }));
const log = (message) => deck.send(JSON.stringify({ event: "logMessage", payload: { message: `BCOE&M Awards Presenter: ${message}` } }));

deck.onopen = () => {
  deck.send(JSON.stringify({ event: args.registerEvent, uuid: args.pluginUUID }));
  connectApp();
};
deck.onclose = () => process.exit(0);

deck.onmessage = ({ data }) => {
  const { event, action, context, payload } = JSON.parse(data);

  switch (event) {
    case "willAppear":
      if (payload.controller !== "Encoder") return;
      dials.set(context, action);
      draw(context);
      break;

    case "willDisappear":
      dials.delete(context);
      break;

    case "dialRotate":
      // Turning only moves standby; nothing goes on screen without a press.
      if (action !== NEXT) return;
      for (let i = 0; i < Math.min(Math.abs(payload.ticks), 10); i++) {
        command(context, payload.ticks > 0 ? "next" : "prev");
      }
      break;

    case "dialDown":
      command(context, action === NEXT ? "go" : "hide_all");
      break;
  }
};

function connectApp() {
  app = new WebSocket(APP_URL);
  app.onopen = () => log(`connected to ${APP_URL}`);
  app.onmessage = ({ data }) => {
    const message = JSON.parse(data);
    if (message.error) {
      log(message.error);
      if (sender) toDeck("showAlert", sender);
      return;
    }
    show = message;
    for (const context of dials.keys()) draw(context);
  };
  // onerror is always followed by onclose, which retries.
  app.onerror = () => {};
  app.onclose = () => {
    if (show) log("lost the app; retrying");
    app = null;
    show = null;
    for (const context of dials.keys()) draw(context);
    setTimeout(connectApp, 2000);
  };
}

function command(context, cmd) {
  sender = context;
  if (app?.readyState === WebSocket.OPEN) app.send(JSON.stringify({ cmd }));
  else toDeck("showAlert", context);
}

function draw(context) {
  const live = dials.get(context) === LIVE;
  const feedback = live ? drawLive() : drawNext();

  if (!show) {
    feedback.table = { value: "Offline", color: "#8a8a8a" };
    feedback.category = { value: "Start the BCOE&M Awards Presenter app", color: "#ff6b6b" };
  } else if (show.obs !== "connected") {
    feedback.category = { value: "OBS not connected", color: "#ff6b6b" };
  }
  toDeck("setFeedback", context, feedback);
}

function drawLive() {
  const cue = show?.live;
  const place = (n) => ({ value: ["1st", "2nd", "3rd"][n - 1], color: show?.revealed?.[n] ? "#ffffff" : "#6e6e6e" });

  return {
    p1: place(1),
    p2: place(2),
    p3: place(3),
    table: { value: cue ? `Table ${cue.table}` : "—", color: "#ffffff" },
    category: { value: cue ? cue.category : "Nothing live yet", color: "#e0e0e0" },
  };
}

function drawNext() {
  const cue = show?.standby;

  return {
    info: cue ? `${cue.position} / ${show.count}` : "",
    table: { value: cue ? `Table ${cue.table}` : "—", color: "#ffffff" },
    category: { value: cue ? cue.category : show?.count ? "End of the list" : "No results loaded", color: "#e0e0e0" },
  };
}
