defmodule BcoemObsAwardsPresenterWeb.Router do
  use BcoemObsAwardsPresenterWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BcoemObsAwardsPresenterWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", BcoemObsAwardsPresenterWeb do
    pipe_through :browser

    live "/", ShowLive
  end

  # For Stream Deck buttons. GET is accepted so the built-in "Website" action
  # can call these with "GET request in background" enabled.
  scope "/api", BcoemObsAwardsPresenterWeb do
    pipe_through :api

    for action <- [:go, :next, :prev, :hide_all] do
      path = "/" <> String.replace(to_string(action), "_", "-")
      get path, ApiController, action
      post path, ApiController, action
    end

    get "/deck", ApiController, :deck
  end
end
