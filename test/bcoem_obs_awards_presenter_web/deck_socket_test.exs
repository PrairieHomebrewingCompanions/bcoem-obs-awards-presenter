defmodule BcoemObsAwardsPresenterWeb.DeckSocketTest do
  # Show and Obs are singletons, so these run one at a time.
  use ExUnit.Case, async: false

  alias BcoemObsAwardsPresenter.{FakeObs, Obs, Show}
  alias BcoemObsAwardsPresenterWeb.DeckSocket

  @port 4467
  @csv """
  Table,Name,Style,Place,"Last Name","First Name","Entry Name",Club,Co-Brewer
  1,"Table 1 - Light Lager",Festbier,1,Lindqvist,Ada,"Harvest Moon","Riverside Brewers Guild",
  3,"Table 3 - European Amber Lager",Märzen,1,Chen,Avery,"Yes, It's Amber","Hilltop Homebrewers",
  """

  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "bcoem_obs_awards_presenter_test_#{System.unique_integer([:positive])}.csv"
      )

    File.write!(path, @csv)
    on_exit(fn -> File.rm(path) end)

    start_supervised!({FakeObs, port: @port, test: self(), password: "secret", missing: %{}})
    Phoenix.PubSub.subscribe(BcoemObsAwardsPresenter.PubSub, Obs.topic())
    start_supervised!({Obs, url: "ws://127.0.0.1:#{@port}", password: "secret"})
    assert_receive {:obs_status, :connected, _}, 2_000

    {:ok, _} = Show.load_csv(path)
    :ok
  end

  test "pushes the show summary on connect" do
    assert {:push, {:text, json}, _state} = DeckSocket.init(%{})

    assert %{
             "obs" => "connected",
             "count" => 2,
             "live" => nil,
             "standby" => %{"table" => 1, "category" => "Light Lager", "position" => 1}
           } = Jason.decode!(json)
  end

  test "commands change the show, and the change is pushed" do
    {:push, _, state} = DeckSocket.init(%{})
    assert {:ok, ^state} = DeckSocket.handle_in({~s({"cmd":"next"}), opcode: :text}, state)

    assert_receive {:show, show}
    assert {:push, {:text, json}, ^state} = DeckSocket.handle_info({:show, show}, state)
    assert %{"standby" => %{"table" => 3, "position" => 2}} = Jason.decode!(json)
  end

  test "failed and unknown commands are answered with an error" do
    {:push, _, state} = DeckSocket.init(%{})

    assert {:push, {:text, json}, ^state} =
             DeckSocket.handle_in({~s({"cmd":"explode"}), opcode: :text}, state)

    assert %{"error" => "Unknown command" <> _} = Jason.decode!(json)
  end
end
