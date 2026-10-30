# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :bcoem_obs_awards_presenter,
  generators: [timestamp_type: :utc_datetime],
  # Append the co-brewer to the brewer line, e.g. "Theo Martin & Sam Abbott".
  co_brewer: true

# OBS naming. GO sets the text of the category source and of
# "<place source> <field label>" for every place and field (e.g.
# "Award 3rd Brewer"), then hides each place source in the overlay scene.
# Places are listed in reveal order.
config :bcoem_obs_awards_presenter, :overlay,
  scene: "Awards Overlay",
  category: "Award Category",
  places: [{3, "Award 3rd"}, {2, "Award 2nd"}, {1, "Award 1st"}],
  fields: [brewer: "Brewer", entry: "Entry", club: "Club", style: "Style"]

# Configure the endpoint
config :bcoem_obs_awards_presenter, BcoemObsAwardsPresenterWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [
      html: BcoemObsAwardsPresenterWeb.ErrorHTML,
      json: BcoemObsAwardsPresenterWeb.ErrorJSON
    ],
    layout: false
  ],
  pubsub_server: BcoemObsAwardsPresenter.PubSub,
  live_view: [signing_salt: "gVmXbLmw"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.28.2",
  bcoem_obs_awards_presenter: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.3",
  bcoem_obs_awards_presenter: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
