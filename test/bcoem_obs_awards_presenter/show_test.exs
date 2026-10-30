defmodule BcoemObsAwardsPresenter.ShowTest do
  # Show and Obs are singletons, so these run one at a time.
  use ExUnit.Case, async: false

  alias BcoemObsAwardsPresenter.{FakeObs, Obs, Show}

  @port 4466
  @csv """
  Table,Name,Style,Place,"Last Name","First Name","Entry Name",Club,Co-Brewer
  1,"Table 1 - Light Lager",Festbier,1,Lindqvist,Ada,"Harvest Moon","Riverside Brewers Guild",
  1,"Table 1 - Light Lager",Festbier,2,Okafor,Jordan,"One More Round",,
  3,"Table 3 - European Amber Lager",Märzen,1,Chen,Avery,"Yes, It's Amber","Hilltop Homebrewers",
  """

  setup context do
    path =
      Path.join(
        System.tmp_dir!(),
        "bcoem_obs_awards_presenter_test_#{System.unique_integer([:positive])}.csv"
      )

    File.write!(path, @csv)
    on_exit(fn -> File.rm(path) end)

    start_supervised!(
      {FakeObs, port: @port, test: self(), password: "secret", missing: context[:missing] || %{}}
    )

    Phoenix.PubSub.subscribe(BcoemObsAwardsPresenter.PubSub, Obs.topic())
    start_supervised!({Obs, url: "ws://127.0.0.1:#{@port}", password: "secret"})
    assert_receive {:fake_obs, obs}, 2_000
    assert_receive {:obs_status, :connected, _}, 2_000

    {:ok, _} = Show.load_csv(path)
    flush_requests()
    {:ok, obs: obs}
  end

  test "GO hides every place, then loads the standby cue's text, then advances standby" do
    assert Show.get().standby == 1
    assert {:ok, show} = Show.go()
    assert {show.live, show.standby} == {1, 3}

    requests = collect_requests()
    hides = for {"SetSceneItemEnabled", d} <- requests, do: d["sceneItemEnabled"]
    assert hides == [false, false, false]

    # Hiding happens before any text changes.
    first_text = Enum.find_index(requests, &match?({"SetInputSettings", _}, &1))

    last_hide =
      requests
      |> Enum.map(&elem(&1, 0))
      |> Enum.reverse()
      |> Enum.find_index(&(&1 == "SetSceneItemEnabled"))

    assert first_text > length(requests) - 1 - last_hide

    texts =
      Map.new(
        for {"SetInputSettings", d} <- requests, do: {d["inputName"], d["inputSettings"]["text"]}
      )

    assert texts["Award Category"] == "Light Lager"
    assert texts["Award 1st Brewer"] == "Ada Lindqvist"
    assert texts["Award 2nd Club"] == ""
    # No 3rd place awarded: its lines are blanked rather than left stale.
    assert texts["Award 3rd Brewer"] == ""
  end

  test "slashes are spaced so OBS can wrap at them" do
    assert Show.wrappable("Spice/Herb/Vegetable Beer") == "Spice / Herb / Vegetable Beer"
    assert Show.wrappable("Fruit / Spice") == "Fruit / Spice"
    assert Show.wrappable("Light Lager") == "Light Lager"
  end

  test "a quick double GO only advances once" do
    {:ok, _} = Show.go()
    {:ok, show} = Show.go()
    assert {show.live, show.standby} == {1, 3}
  end

  test "selecting a cue puts it on standby without going live" do
    {:ok, show} = Show.standby(3)
    assert {show.live, show.standby} == {nil, 3}
    assert collect_requests() == []

    {:ok, show} = Show.go()
    assert {show.live, show.standby} == {3, nil}
    # Wait out the double-tap guard.
    Process.sleep(800)
    assert {:error, "Nothing on standby"} = Show.go()
  end

  test "tracks reveals from OBS scene item events", %{obs: obs} do
    {:ok, show} = Show.go()
    assert show.revealed == %{1 => false, 2 => false, 3 => false}

    send(
      obs,
      {:emit, "SceneItemEnableStateChanged",
       %{
         sceneName: "Awards Overlay",
         sceneItemId: :erlang.phash2("3rd", 1000),
         sceneItemEnabled: true
       }}
    )

    wait_until(fn -> Show.get().revealed[3] end)
    assert Show.get().revealed[1] == false
  end

  @tag missing: %{"Award 1st Style" => "No source was found by the name of `Award 1st Style`."}
  test "a missing text source still goes, with a warning" do
    assert {:ok, show} = Show.go()
    assert show.live == 1
    assert {:warning, "Loaded, but: SetInputSettings: No source was found" <> _} = show.alert
  end

  @tag missing: %{"Award 2nd" => "No scene items were found."}
  test "a missing place source refuses to GO" do
    assert {:error, "Couldn't find \"Award 2nd\"" <> _} = Show.go()
    assert Show.get().live == nil
  end

  defp collect_requests(acc \\ []) do
    receive do
      {:obs_request, type, data} -> collect_requests([{type, data} | acc])
    after
      50 -> Enum.reverse(acc)
    end
  end

  defp flush_requests, do: collect_requests() && :ok

  defp wait_until(fun, tries \\ 50) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("condition never became true")
      true -> Process.sleep(20) && wait_until(fun, tries - 1)
    end
  end
end
