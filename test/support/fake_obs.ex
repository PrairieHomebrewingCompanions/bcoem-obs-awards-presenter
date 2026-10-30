defmodule BcoemObsAwardsPresenter.FakeObs do
  @moduledoc """
  A tiny stand-in for OBS's websocket server. It authenticates like OBS,
  answers requests, and forwards every request it receives to the test
  process as `{:obs_request, type, data}`.
  """
  @behaviour WebSock

  @salt "salt"
  @challenge "challenge"

  def child_spec(opts) do
    plug = {__MODULE__.Plug, opts}

    Supervisor.child_spec(
      {Bandit, plug: plug, port: Keyword.fetch!(opts, :port), startup_log: false},
      []
    )
  end

  defmodule Plug do
    @moduledoc false
    def init(opts), do: opts

    def call(conn, opts) do
      WebSockAdapter.upgrade(conn, BcoemObsAwardsPresenter.FakeObs, Map.new(opts), [])
    end
  end

  @impl true
  def init(state) do
    hello = %{op: 0, d: %{rpcVersion: 1, authentication: %{challenge: @challenge, salt: @salt}}}
    {:push, {:text, Jason.encode!(hello)}, state}
  end

  @impl true
  def handle_in({json, _opts}, state) do
    handle(Jason.decode!(json), state)
  end

  @impl true
  def handle_info({:emit, type, data}, state) do
    {:push, {:text, Jason.encode!(%{op: 5, d: %{eventType: type, eventData: data}})}, state}
  end

  defp handle(%{"op" => 1, "d" => %{"authentication" => auth}}, state) do
    secret = :crypto.hash(:sha256, state.password <> @salt) |> Base.encode64()

    if auth == :crypto.hash(:sha256, secret <> @challenge) |> Base.encode64() do
      send(state.test, {:fake_obs, self()})
      {:push, {:text, Jason.encode!(%{op: 2, d: %{negotiatedRpcVersion: 1}})}, state}
    else
      {:stop, :normal, {4009, "Authentication failed."}, state}
    end
  end

  defp handle(%{"op" => 8, "d" => %{"requestId" => id, "requests" => requests}}, state) do
    results = for r <- requests, do: respond(r["requestType"], r["requestData"] || %{}, state)
    {:push, {:text, Jason.encode!(%{op: 9, d: %{requestId: id, results: results}})}, state}
  end

  defp respond(type, data, state) do
    send(state.test, {:obs_request, type, data})

    case Map.get(state.missing, data["inputName"] || data["sourceName"]) do
      nil ->
        %{
          requestType: type,
          requestStatus: %{result: true, code: 100},
          responseData: response(type, data)
        }

      comment ->
        %{requestType: type, requestStatus: %{result: false, code: 600, comment: comment}}
    end
  end

  defp response("GetSceneItemId", %{"sourceName" => "Award " <> place}),
    do: %{sceneItemId: :erlang.phash2(place, 1000)}

  defp response("GetSceneItemEnabled", _), do: %{sceneItemEnabled: false}
  defp response(_type, _data), do: %{}
end
