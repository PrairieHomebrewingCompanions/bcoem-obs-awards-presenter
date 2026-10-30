defmodule BcoemObsAwardsPresenterWeb.ApiController do
  @moduledoc """
  Endpoints for Stream Deck buttons: `/api/go`, `/api/next`, `/api/prev` and
  `/api/hide-all`, plus the `/api/deck` WebSocket for the Stream Deck + dials.
  """
  use BcoemObsAwardsPresenterWeb, :controller

  alias BcoemObsAwardsPresenter.Show

  def go(conn, _params), do: respond(conn, Show.go())
  def next(conn, _params), do: respond(conn, Show.step(:next))
  def prev(conn, _params), do: respond(conn, Show.step(:prev))
  def hide_all(conn, _params), do: respond(conn, Show.hide_all())

  def deck(conn, _params) do
    conn
    |> WebSockAdapter.upgrade(BcoemObsAwardsPresenterWeb.DeckSocket, %{}, timeout: :infinity)
    |> halt()
  end

  defp respond(conn, {:ok, show}) do
    json(conn, %{ok: true, live: summary(show, show.live), standby: summary(show, show.standby)})
  end

  defp respond(conn, {:error, message}) do
    conn |> put_status(:conflict) |> json(%{ok: false, error: message})
  end

  defp summary(_show, nil), do: nil

  defp summary(show, table) do
    cue = Show.cue(show, table)
    %{table: cue.table, category: cue.category}
  end
end
