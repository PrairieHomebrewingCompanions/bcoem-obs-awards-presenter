defmodule BcoemObsAwardsPresenterWeb.DeckSocket do
  @moduledoc """
  A plain WebSocket for the Stream Deck + plugin (see `streamdeck/`).

  On connect, and after every change to the show, it pushes a summary:

      {"obs": "connected", "count": 31,
       "live": {"table": 4, "category": "Bock", "position": 4},
       "standby": {"table": 5, "category": "Light Hybrid Beer", "position": 5},
       "revealed": {"1": false, "2": true, "3": true}}

  The plugin sends commands as `{"cmd": "go" | "next" | "prev" | "hide_all"}`.
  A command that fails is answered with `{"error": message}`.
  """
  @behaviour WebSock

  alias BcoemObsAwardsPresenter.Show

  @commands %{
    "go" => &Show.go/0,
    "next" => &__MODULE__.next/0,
    "prev" => &__MODULE__.prev/0,
    "hide_all" => &Show.hide_all/0
  }

  @impl true
  def init(state) do
    Show.subscribe()
    {:push, push(Show.get()), state}
  end

  @impl true
  def handle_in({json, opcode: :text}, state) do
    with {:ok, %{"cmd" => cmd}} <- Jason.decode(json),
         {:ok, command} <- Map.fetch(@commands, cmd) do
      case command.() do
        {:ok, _show} -> {:ok, state}
        {:error, message} -> {:push, error(message), state}
      end
    else
      _ -> {:push, error("Unknown command: #{json}"), state}
    end
  end

  @impl true
  def handle_info({:show, show}, state), do: {:push, push(show), state}
  def handle_info(_message, state), do: {:ok, state}

  @doc false
  def next, do: Show.step(:next)
  @doc false
  def prev, do: Show.step(:prev)

  @doc "The summary the plugin draws from: just what fits on the touch strip."
  def summary(%Show{} = show) do
    tables = Enum.map(show.cues, & &1.table)

    %{
      obs: show.obs,
      count: length(tables),
      live: cue_summary(show, tables, show.live),
      standby: cue_summary(show, tables, show.standby),
      revealed: Map.new(show.revealed, fn {place, shown} -> {to_string(place), shown} end)
    }
  end

  defp cue_summary(_show, _tables, nil), do: nil

  defp cue_summary(show, tables, table) do
    cue = Show.cue(show, table)
    position = Enum.find_index(tables, &(&1 == table)) + 1
    %{table: cue.table, category: cue.category, position: position}
  end

  defp push(show), do: {:text, Jason.encode!(summary(show))}
  defp error(message), do: {:text, Jason.encode!(%{error: message})}
end
