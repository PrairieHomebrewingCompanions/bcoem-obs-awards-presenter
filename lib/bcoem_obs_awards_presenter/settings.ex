defmodule BcoemObsAwardsPresenter.Settings do
  @moduledoc """
  Where the OBS connection settings come from, and saving the ones entered on
  the control page.

  Settings saved from the page win over the `OBS_URL` and `OBS_PASSWORD`
  environment variables.

  Saved settings live outside the repo, in the user's config folder (on macOS,
  `~/Library/Application Support/bcoem_obs_awards_presenter/settings.json`).
  """

  @doc "The OBS connection options for `BcoemObsAwardsPresenter.Obs`: `[url: ..., password: ...]`."
  def obs do
    {url, password, _source} = resolve()
    [url: url, password: password]
  end

  @doc """
  The OBS URL and where the password comes from, for the control page:
  `:saved`, `:env` or `nil` (none).
  """
  def obs_info do
    {url, _password, source} = resolve()
    %{url: url, password_source: source}
  end

  @doc """
  Saves the OBS URL, and the password unless it's blank (blank keeps the
  current one).
  """
  def save_obs(url, password) do
    saved = read()

    saved =
      saved
      |> Map.put("obs_url", String.trim(url))
      |> then(&if(password == "", do: &1, else: Map.put(&1, "obs_password", password)))

    write(saved)
  end

  @doc "Forgets the saved password, falling back to `OBS_PASSWORD` if set."
  def forget_obs_password, do: read() |> Map.delete("obs_password") |> write()

  defp resolve do
    saved = read()
    env = Application.get_env(:bcoem_obs_awards_presenter, :obs, [])
    url = present(saved["obs_url"]) || env[:url] || "ws://127.0.0.1:4455"

    {password, source} =
      cond do
        password = present(saved["obs_password"]) -> {password, :saved}
        password = present(env[:password]) -> {password, :env}
        true -> {nil, nil}
      end

    {url, password, source}
  end

  defp read do
    with {:ok, json} <- File.read(path()),
         {:ok, %{} = saved} <- Jason.decode(json) do
      saved
    else
      _ -> %{}
    end
  end

  defp write(saved) do
    File.mkdir_p!(Path.dirname(path()))
    File.write!(path(), Jason.encode_to_iodata!(saved, pretty: true))
    # It holds a password.
    File.chmod!(path(), 0o600)
  end

  defp path do
    Application.get_env(:bcoem_obs_awards_presenter, :settings_path) ||
      Path.join(:filename.basedir(:user_config, "bcoem_obs_awards_presenter"), "settings.json")
  end

  defp present(value) when is_binary(value) and value != "", do: value
  defp present(_), do: nil
end
