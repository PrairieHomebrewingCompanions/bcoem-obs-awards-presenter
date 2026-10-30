import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :bcoem_obs_awards_presenter, BcoemObsAwardsPresenterWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "EApvnanksoYddc148e71/X08Ev/1Q4r8Be5eRPPJFvsH2d+RjPoA3BrjB5C6RfLG",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Don't try to reach a real OBS from tests
config :bcoem_obs_awards_presenter, start_obs: false

# Keep tests away from the real saved settings
config :bcoem_obs_awards_presenter,
  settings_path: Path.join(System.tmp_dir!(), "bcoem_obs_awards_presenter_test/settings.json")
