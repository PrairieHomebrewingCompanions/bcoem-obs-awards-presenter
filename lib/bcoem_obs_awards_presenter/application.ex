defmodule BcoemObsAwardsPresenter.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BcoemObsAwardsPresenterWeb.Telemetry,
      {DNSCluster,
       query: Application.get_env(:bcoem_obs_awards_presenter, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: BcoemObsAwardsPresenter.PubSub},
      # Show subscribes to OBS status, so it starts first.
      {BcoemObsAwardsPresenter.Show,
       csv_path: Application.get_env(:bcoem_obs_awards_presenter, :csv_path)},
      obs_client(),
      # Start to serve requests, typically the last entry
      BcoemObsAwardsPresenterWeb.Endpoint
    ]

    children = Enum.reject(children, &is_nil/1)

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BcoemObsAwardsPresenter.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp obs_client do
    if Application.get_env(:bcoem_obs_awards_presenter, :start_obs, true) do
      # Connection settings come from BcoemObsAwardsPresenter.Settings when it starts.
      {BcoemObsAwardsPresenter.Obs, []}
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BcoemObsAwardsPresenterWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
