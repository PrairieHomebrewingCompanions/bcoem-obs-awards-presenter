defmodule BcoemObsAwardsPresenterWeb.ShowLiveTest do
  # Show is a singleton, so these run one at a time.
  use BcoemObsAwardsPresenterWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias BcoemObsAwardsPresenter.Show

  @csv """
  Table,Name,Style,Place,"Last Name","First Name","Entry Name",Club,Co-Brewer
  1,"Table 1 - Light Lager",Festbier,1,Lindqvist,Ada,"Harvest Moon","Riverside Brewers Guild",
  3,"Table 3 - European Amber Lager",Märzen,1,Chen,Avery,"Yes, It's Amber","Hilltop Homebrewers",
  """

  defp upload(view, name, content \\ @csv) do
    view
    |> file_input("#csv-form", :csv, [%{name: name, content: content, type: "text/csv"}])
    |> render_upload(name)
  end

  test "an uploaded CSV builds the cue list", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    upload(view, "winners.csv")

    assert has_element?(view, "#cue-1")
    assert has_element?(view, "#cue-3")
    assert has_element?(view, "#csv-form", "winners.csv")
  end

  test "once a CSV is loaded, the BCOE&M help moves behind a link", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    upload(view, "winners.csv")

    refute has_element?(view, "#csv-help")
    assert has_element?(view, "#csv-help-toggle")
    assert has_element?(view, "#csv-help-panel", "Winners: Limited Data")
  end

  test "the wrong export says which one to use", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    upload(view, "entries.csv", "Table,Name\n1,x\n")

    assert has_element?(view, "[role=alert]", "Winners: Limited Data")
  end

  test "uploading a re-download keeps the show's place", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    upload(view, "winners.csv")
    {:ok, _} = Show.standby(3)

    upload(view, "winners (1).csv")

    assert Show.get().standby == 3
    assert has_element?(view, "#csv-form", "winners (1).csv")
  end

  test "a file that isn't a CSV is refused", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> file_input("#csv-form", :csv, [%{name: "notes.txt", content: "hi", type: "text/plain"}])
    |> render_upload("notes.txt")

    assert has_element?(view, "#csv-form .text-error")
  end

  describe "OBS settings" do
    setup do
      path = Application.fetch_env!(:bcoem_obs_awards_presenter, :settings_path)
      File.rm(path)
      on_exit(fn -> File.rm(path) end)
    end

    test "saving the form stores the address and password", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> form("#obs-settings-form", %{"url" => "ws://127.0.0.1:4460", "password" => "pw"})
      |> render_submit()

      assert BcoemObsAwardsPresenter.Settings.obs() == [
               url: "ws://127.0.0.1:4460",
               password: "pw"
             ]

      assert has_element?(view, "#forget-obs-password")
      # Tests don't run the OBS client, so there's nothing to reconnect.
      assert render(view) =~ "the OBS client isn&#39;t running"
    end
  end
end
