defmodule BcoemObsAwardsPresenter.Obs do
  @moduledoc """
  A minimal obs-websocket (protocol v5) client.

  Connects in the background and reconnects whenever OBS goes away, so the
  app and OBS can be started in either order. Connection status changes and
  OBS events are broadcast on the `"obs"` PubSub topic as
  `{:obs_status, status, detail}` and `{:obs_event, type, data}`.
  """
  use WebSockex
  require Logger

  @topic "obs"
  @reconnect_ms 2_000
  @request_timeout 5_000
  # Only scene item events (1 <<< 7); used to track which places are revealed.
  @event_subscriptions 128

  def topic, do: @topic

  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}
  end

  @doc """
  Starts the client. `:url` and `:password` default to
  `BcoemObsAwardsPresenter.Settings.obs/0`.
  """
  def start_link(opts) do
    opts = Keyword.merge(BcoemObsAwardsPresenter.Settings.obs(), opts)

    state = %{
      password: Keyword.get(opts, :password),
      status: :connecting,
      last_error: nil,
      pending: %{},
      next_id: 1
    }

    WebSockex.start_link(Keyword.fetch!(opts, :url), __MODULE__, state,
      name: __MODULE__,
      async: true,
      handle_initial_conn_failure: true
    )
  end

  @doc """
  Restarts the client so it connects with the current settings.
  """
  def reconnect do
    with :ok <- Supervisor.terminate_child(BcoemObsAwardsPresenter.Supervisor, __MODULE__),
         {:ok, _pid} <- Supervisor.restart_child(BcoemObsAwardsPresenter.Supervisor, __MODULE__) do
      :ok
    end
  end

  @doc """
  Sends a single request. Returns `{:ok, response_data}` or `{:error, reason}`.
  """
  def request(type, data \\ %{}) do
    await({:request, type, data})
  end

  @doc """
  Sends `[{type, data}]` as one serial batch, executed in order. Returns
  `{:ok, results}` where each result is `{:ok, data}` or `{:error, reason}`.
  """
  def batch(requests) do
    await({:batch, requests})
  end

  defp await(message) do
    ref = make_ref()
    WebSockex.cast(__MODULE__, {message, self(), ref})

    receive do
      {^ref, result} -> result
    after
      @request_timeout -> {:error, "OBS did not respond"}
    end
  end

  ## Callbacks

  @impl true
  def handle_connect(_conn, state) do
    {:ok, %{state | status: :connecting}}
  end

  @impl true
  def handle_frame({:text, json}, state) do
    json |> Jason.decode!() |> handle_message(state)
  end

  def handle_frame(_frame, state), do: {:ok, state}

  @impl true
  def handle_cast({_message, from, ref}, %{status: status} = state) when status != :connected do
    send(from, {ref, {:error, "Not connected to OBS"}})
    {:ok, state}
  end

  def handle_cast({{:request, type, data}, from, ref}, state) do
    {id, state} = track(state, from, ref, :request)
    send_op(6, %{requestType: type, requestId: id, requestData: data}, state)
  end

  def handle_cast({{:batch, requests}, from, ref}, state) do
    {id, state} = track(state, from, ref, :batch)

    requests = for {type, data} <- requests, do: %{requestType: type, requestData: data}

    send_op(
      8,
      %{requestId: id, haltOnFailure: false, executionType: 0, requests: requests},
      state
    )
  end

  @impl true
  def handle_disconnect(%{reason: reason}, state) do
    for {_id, {from, ref, _kind}} <- state.pending do
      send(from, {ref, {:error, "Lost connection to OBS"}})
    end

    # Retries every couple of seconds; only report when something changes.
    error = describe(reason)

    if error != state.last_error do
      Logger.warning("OBS disconnected: #{inspect(reason)}")
      broadcast({:obs_status, :disconnected, error})
    end

    Process.sleep(@reconnect_ms)
    {:reconnect, %{state | status: :disconnected, last_error: error, pending: %{}}}
  end

  ## Protocol

  # Hello
  defp handle_message(%{"op" => 0, "d" => hello}, state) do
    identify =
      case hello do
        %{"authentication" => %{"challenge" => challenge, "salt" => salt}} ->
          %{rpcVersion: 1, authentication: auth(state.password || "", salt, challenge)}

        _ ->
          %{rpcVersion: 1}
      end

    send_op(1, Map.put(identify, :eventSubscriptions, @event_subscriptions), state)
  end

  # Identified
  defp handle_message(%{"op" => 2}, state) do
    Logger.info("Connected to OBS")
    broadcast({:obs_status, :connected, nil})
    {:ok, %{state | status: :connected, last_error: nil}}
  end

  # Event
  defp handle_message(%{"op" => 5, "d" => %{"eventType" => type} = d}, state) do
    broadcast({:obs_event, type, Map.get(d, "eventData", %{})})
    {:ok, state}
  end

  # RequestResponse
  defp handle_message(%{"op" => 7, "d" => %{"requestId" => id} = d}, state) do
    reply(state, id, result(d))
  end

  # RequestBatchResponse
  defp handle_message(%{"op" => 9, "d" => %{"requestId" => id, "results" => results}}, state) do
    reply(state, id, {:ok, Enum.map(results, &result/1)})
  end

  defp handle_message(_message, state), do: {:ok, state}

  defp result(%{"requestStatus" => %{"result" => true}} = d),
    do: {:ok, Map.get(d, "responseData", %{})}

  defp result(%{"requestType" => type, "requestStatus" => status}),
    do: {:error, "#{type}: #{status["comment"] || "error code #{status["code"]}"}"}

  defp auth(password, salt, challenge) do
    secret = :crypto.hash(:sha256, password <> salt) |> Base.encode64()
    :crypto.hash(:sha256, secret <> challenge) |> Base.encode64()
  end

  defp track(state, from, ref, kind) do
    id = Integer.to_string(state.next_id)

    {id,
     %{state | next_id: state.next_id + 1, pending: Map.put(state.pending, id, {from, ref, kind})}}
  end

  defp reply(state, id, result) do
    case Map.pop(state.pending, id) do
      {{from, ref, _kind}, pending} ->
        send(from, {ref, result})
        {:ok, %{state | pending: pending}}

      {nil, _} ->
        {:ok, state}
    end
  end

  defp send_op(op, data, state) do
    {:reply, {:text, Jason.encode!(%{op: op, d: data})}, state}
  end

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(BcoemObsAwardsPresenter.PubSub, @topic, message)
  end

  defp describe({:remote, 4009, _}), do: "Authentication failed: check the OBS password"
  defp describe({:remote, _code, message}) when is_binary(message) and message != "", do: message

  defp describe(%WebSockex.ConnError{original: :econnrefused}),
    do: "OBS isn't running, or the WebSocket server is off"

  defp describe(reason), do: inspect(reason)
end
