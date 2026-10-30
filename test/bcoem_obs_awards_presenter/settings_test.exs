defmodule BcoemObsAwardsPresenter.SettingsTest do
  # Changes application env and shared files.
  use ExUnit.Case, async: false

  alias BcoemObsAwardsPresenter.Settings

  setup do
    settings = Application.fetch_env!(:bcoem_obs_awards_presenter, :settings_path)
    env = Application.get_env(:bcoem_obs_awards_presenter, :obs)
    File.rm(settings)
    Application.put_env(:bcoem_obs_awards_presenter, :obs, url: nil, password: nil)

    on_exit(fn ->
      File.rm(settings)
      Application.put_env(:bcoem_obs_awards_presenter, :obs, env)
    end)

    {:ok, settings: settings}
  end

  test "with nothing set, connects to local OBS without a password" do
    assert Settings.obs() == [url: "ws://127.0.0.1:4455", password: nil]
    assert Settings.obs_info().password_source == nil
  end

  test "saved settings beat the environment" do
    Application.put_env(:bcoem_obs_awards_presenter, :obs,
      url: "ws://127.0.0.1:4456",
      password: "from-env"
    )

    assert Settings.obs() == [url: "ws://127.0.0.1:4456", password: "from-env"]

    Settings.save_obs("ws://127.0.0.1:4457", "saved")
    assert Settings.obs() == [url: "ws://127.0.0.1:4457", password: "saved"]
    assert Settings.obs_info().password_source == :saved
  end

  test "a blank password keeps the saved one; forgetting falls back", %{settings: settings} do
    Settings.save_obs("ws://127.0.0.1:4455", "saved")
    Settings.save_obs("ws://127.0.0.1:4455", "")
    assert Settings.obs()[:password] == "saved"
    assert File.stat!(settings).mode |> Bitwise.band(0o777) == 0o600

    Settings.forget_obs_password()
    assert Settings.obs()[:password] == nil
  end
end
