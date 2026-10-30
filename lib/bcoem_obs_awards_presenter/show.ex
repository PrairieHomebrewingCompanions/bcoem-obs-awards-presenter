defmodule BcoemObsAwardsPresenter.Show do
  @moduledoc """
  The running show: the cue list, which cue is on standby, which is live, and
  which places are currently revealed in OBS.

  Like QLab, GO loads the standby cue and moves standby to the next cue in
  the list. Loading a cue first hides every place so the previous winners can
  never flash on screen; revealing places is left to the Stream Deck.

  Every change is broadcast as `{:show, state}` on the `"show"` topic.
  """
  use GenServer
  require Logger

  alias BcoemObsAwardsPresenter.{Obs, Results}

  @topic "show"
  # Protects against a double-tapped Stream Deck button skipping a category.
  @go_debounce_ms 750
  @call_timeout 15_000

  defstruct csv_path: nil,
            csv_name: nil,
            cues: [],
            standby: nil,
            live: nil,
            done: MapSet.new(),
            obs: :connecting,
            obs_detail: nil,
            item_ids: %{},
            revealed: %{},
            setup: nil,
            alert: nil,
            last_go: nil

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def subscribe, do: Phoenix.PubSub.subscribe(BcoemObsAwardsPresenter.PubSub, @topic)

  def get, do: call(:get)
  def go, do: call(:go)
  def standby(table), do: call({:standby, table})
  def step(direction) when direction in [:next, :prev], do: call({:step, direction})
  def hide_all, do: call(:hide_all)

  @doc """
  Loads the winners CSV at `path`. `name` is the file name to report, for an
  uploaded copy saved under another name.
  """
  def load_csv(path, name \\ nil), do: call({:load_csv, path, name})
  def check_setup, do: call(:check_setup)
  def build_missing, do: call(:build_missing)
  def dismiss_alert, do: call(:dismiss_alert)

  defp call(message), do: GenServer.call(__MODULE__, message, @call_timeout)

  @doc "Looks up a cue by table number."
  def cue(%__MODULE__{cues: cues}, table), do: Enum.find(cues, &(&1.table == table))

  @doc "The overlay naming configuration (see config/config.exs)."
  def overlay, do: Application.fetch_env!(:bcoem_obs_awards_presenter, :overlay)

  @doc "The OBS text source name for a place's field, e.g. \"Award 3rd Brewer\"."
  def text_source(place_source, label), do: "#{place_source} #{label}"

  ## Callbacks

  @impl true
  def init(opts) do
    Phoenix.PubSub.subscribe(BcoemObsAwardsPresenter.PubSub, Obs.topic())
    state = %__MODULE__{}

    case Keyword.get(opts, :csv_path) do
      path when path in [nil, ""] -> {:ok, state}
      path -> {:ok, state, {:continue, {:load_csv, path}}}
    end
  end

  @impl true
  def handle_continue({:load_csv, path}, state) do
    {_reply, state} = do_load_csv(state, path, nil)
    {:noreply, state}
  end

  @impl true
  def handle_call(:get, _from, state), do: {:reply, state, state}

  # Fail fast rather than waiting out a request timeout while OBS is away.
  def handle_call(message, _from, %{obs: status} = state)
      when status != :connected and message in [:go, :hide_all, :check_setup, :build_missing] do
    fail(
      state,
      "Not connected to OBS" <> if(state.obs_detail, do: ": #{state.obs_detail}", else: "")
    )
  end

  def handle_call(:go, _from, state) do
    now = System.monotonic_time(:millisecond)

    cond do
      state.last_go && now - state.last_go < @go_debounce_ms ->
        {:reply, {:ok, state}, state}

      is_nil(state.standby) ->
        fail(state, "Nothing on standby")

      true ->
        cue = cue(state, state.standby)

        case load_cue(cue) do
          {:ok, item_ids, warnings} ->
            Logger.info("GO: Table #{cue.table} - #{cue.category}")

            changed(%{
              state
              | live: cue.table,
                standby: next_table(state.cues, cue.table),
                done: MapSet.put(state.done, cue.table),
                item_ids: item_ids,
                revealed: Map.new(item_ids, fn {_id, place} -> {place, false} end),
                last_go: now,
                alert: warnings_alert(warnings)
            })

          {:error, message} ->
            fail(state, message)
        end
    end
  end

  def handle_call({:standby, table}, _from, state) do
    if cue(state, table),
      do: changed(%{state | standby: table}),
      else: fail(state, "No table #{table}")
  end

  def handle_call({:step, direction}, _from, %{cues: [_ | _] = cues} = state) do
    tables = Enum.map(cues, & &1.table)

    standby =
      case {direction, Enum.find_index(tables, &(&1 == state.standby))} do
        {:next, nil} -> List.first(tables)
        {:prev, nil} -> List.last(tables)
        {:next, i} -> Enum.at(tables, min(i + 1, length(tables) - 1))
        {:prev, i} -> Enum.at(tables, max(i - 1, 0))
      end

    changed(%{state | standby: standby})
  end

  def handle_call({:step, _direction}, _from, state), do: {:reply, {:ok, state}, state}

  def handle_call(:hide_all, _from, state) do
    with {:ok, item_ids} <- fetch_item_ids(),
         {:ok, _results} <- Obs.batch(hide_requests(item_ids)) do
      changed(%{
        state
        | item_ids: item_ids,
          revealed: Map.new(item_ids, fn {_, p} -> {p, false} end)
      })
    else
      {:error, message} -> fail(state, message)
    end
  end

  def handle_call({:load_csv, path, name}, _from, state) do
    {reply, state} = do_load_csv(state, path, name)
    broadcast(state)
    {:reply, reply, state}
  end

  def handle_call(:check_setup, _from, state) do
    case inspect_obs() do
      {:ok, obs} -> changed(%{state | setup: setup_checklist(obs), alert: nil})
      {:error, message} -> fail(state, message)
    end
  end

  def handle_call(:build_missing, _from, state) do
    with {:ok, obs} <- inspect_obs(),
         :ok <- create_missing(obs),
         {:ok, obs} <- inspect_obs() do
      state = refresh_reveals(state)

      changed(%{
        state
        | setup: setup_checklist(obs),
          alert: {:info, "Created missing OBS sources"}
      })
    else
      {:error, message} -> fail(state, message)
    end
  end

  def handle_call(:dismiss_alert, _from, state), do: changed(%{state | alert: nil})

  @impl true
  def handle_info({:obs_status, :connected, _detail}, state) do
    state = refresh_reveals(%{state | obs: :connected, obs_detail: nil})
    broadcast(state)
    {:noreply, state}
  end

  def handle_info({:obs_status, status, detail}, state) do
    state = %{state | obs: status, obs_detail: detail}
    broadcast(state)
    {:noreply, state}
  end

  def handle_info({:obs_event, "SceneItemEnableStateChanged", data}, state) do
    %{"sceneName" => scene, "sceneItemId" => id, "sceneItemEnabled" => enabled} = data

    case {scene == overlay()[:scene], Map.fetch(state.item_ids, id)} do
      {true, {:ok, place}} ->
        state = put_in(state.revealed[place], enabled)
        broadcast(state)
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  # Ignore other events and late replies from timed-out OBS requests.
  def handle_info(_message, state), do: {:noreply, state}

  ## Cue loading

  defp load_cue(cue) do
    %{category: category, places: places, fields: fields} = Map.new(overlay())

    texts =
      [{category, cue.category}] ++
        for {place, source} <- places, {field, label} <- fields do
          entry = Map.get(cue.places, place)
          {text_source(source, label), (entry && Map.get(entry, field)) || ""}
        end

    text_requests =
      for {input, text} <- texts do
        {"SetInputSettings",
         %{inputName: input, inputSettings: %{text: wrappable(text)}, overlay: true}}
      end

    with {:ok, item_ids} <- fetch_item_ids(),
         {:ok, results} <- Obs.batch(hide_requests(item_ids) ++ text_requests) do
      {:ok, item_ids, for({:error, message} <- results, do: message)}
    end
  end

  @doc """
  Spaces out slashes so OBS can wrap at them: "Spice/Herb/Vegetable Beer"
  becomes "Spice / Herb / Vegetable Beer". OBS's FreeType2 text source only
  breaks lines at spaces and otherwise splits words mid-glyph.
  """
  def wrappable(text), do: String.replace(text, ~r{\s*/\s*}, " / ")

  # Returns `%{scene_item_id => place}` for the place sources in the overlay scene.
  defp fetch_item_ids do
    %{scene: scene, places: places} = Map.new(overlay())

    requests =
      for {_place, source} <- places,
          do: {"GetSceneItemId", %{sceneName: scene, sourceName: source}}

    with {:ok, results} <- Obs.batch(requests) do
      places
      |> Enum.zip(results)
      |> Enum.reduce_while({:ok, %{}}, fn
        {{place, _}, {:ok, %{"sceneItemId" => id}}}, {:ok, acc} ->
          {:cont, {:ok, Map.put(acc, id, place)}}

        {{_, source}, {:error, _}}, _acc ->
          {:halt,
           {:error, ~s(Couldn't find "#{source}" in scene "#{scene}". Run "Check OBS setup".)}}
      end)
    end
  end

  defp hide_requests(item_ids) do
    scene = overlay()[:scene]

    for {id, _place} <- item_ids do
      {"SetSceneItemEnabled", %{sceneName: scene, sceneItemId: id, sceneItemEnabled: false}}
    end
  end

  # Reads which places are currently visible, e.g. after (re)connecting to OBS.
  defp refresh_reveals(state) do
    scene = overlay()[:scene]

    with {:ok, item_ids} <- fetch_item_ids(),
         requests =
           for(
             {id, _} <- item_ids,
             do: {"GetSceneItemEnabled", %{sceneName: scene, sceneItemId: id}}
           ),
         {:ok, results} <- Obs.batch(requests) do
      revealed =
        item_ids
        |> Enum.zip(results)
        |> Map.new(fn {{_id, place}, result} ->
          {place, match?({:ok, %{"sceneItemEnabled" => true}}, result)}
        end)

      %{state | item_ids: item_ids, revealed: revealed}
    else
      _ -> state
    end
  end

  ## OBS setup

  defp inspect_obs do
    scene = overlay()[:scene]

    case Obs.batch([
           {"GetSceneList", %{}},
           {"GetInputList", %{}},
           {"GetSceneItemList", %{sceneName: scene}},
           {"GetInputKindList", %{}}
         ]) do
      {:ok, [{:ok, scenes}, {:ok, inputs}, items, {:ok, kinds}]} ->
        {:ok,
         %{
           scenes: MapSet.new(scenes["scenes"], & &1["sceneName"]),
           inputs: MapSet.new(inputs["inputs"], & &1["inputName"]),
           overlay_items:
             case items do
               {:ok, %{"sceneItems" => items}} -> MapSet.new(items, & &1["sourceName"])
               _ -> MapSet.new()
             end,
           text_kind:
             if("text_gdiplus_v3" in kinds["inputKinds"],
               do: "text_gdiplus_v3",
               else: "text_ft2_source_v2"
             )
         }}

      {:ok, results} ->
        {:error,
         Enum.find_value(results, fn
           {:error, message} -> message
           _ -> nil
         end)}

      error ->
        error
    end
  end

  defp setup_checklist(obs) do
    %{scene: scene, category: category, places: places, fields: fields} = Map.new(overlay())

    [
      {"Scene", scene, MapSet.member?(obs.scenes, scene)},
      {"Text in #{scene}", category, MapSet.member?(obs.inputs, category)}
    ] ++
      Enum.flat_map(places, fn {_place, source} ->
        [{"Scene in #{scene}", source, MapSet.member?(obs.overlay_items, source)}] ++
          for {_field, label} <- fields do
            name = text_source(source, label)
            {"Text in #{source}", name, MapSet.member?(obs.inputs, name)}
          end
      end)
  end

  # Builds the skeleton: the overlay scene, one nested scene per place and
  # every text source, with placeholder text so they can be styled.
  defp create_missing(obs) do
    %{scene: scene, category: category, places: places, fields: fields} = Map.new(overlay())
    text = fn scene_name, name -> create_text(scene_name, name, obs.text_kind) end

    requests =
      [
        !MapSet.member?(obs.scenes, scene) && {"CreateScene", %{sceneName: scene}},
        !MapSet.member?(obs.inputs, category) && text.(scene, category)
      ] ++
        Enum.flat_map(places, fn {_place, source} ->
          [
            !MapSet.member?(obs.scenes, source) && {"CreateScene", %{sceneName: source}},
            !MapSet.member?(obs.overlay_items, source) &&
              {"CreateSceneItem", %{sceneName: scene, sourceName: source}}
          ] ++
            for {_field, label} <- fields do
              name = text_source(source, label)
              !MapSet.member?(obs.inputs, name) && text.(source, name)
            end
        end)

    case Enum.filter(requests, & &1) do
      [] ->
        :ok

      requests ->
        with {:ok, results} <- Obs.batch(requests) do
          case for({:error, message} <- results, do: message) do
            [] -> stack_text_lines(places, fields)
            errors -> {:error, Enum.join(errors, "; ")}
          end
        end
    end
  end

  defp create_text(scene, name, kind) do
    {"CreateInput",
     %{sceneName: scene, inputName: name, inputKind: kind, inputSettings: %{text: name}}}
  end

  # Spreads each place's lines out so new sources don't sit on top of each other.
  defp stack_text_lines(places, fields) do
    lines =
      for {{_place, source}, column} <- Enum.with_index(places),
          {{_field, label}, row} <- Enum.with_index(fields),
          do: {source, text_source(source, label), 100 + column * 600, 700 + row * 70}

    with {:ok, ids} <-
           Obs.batch(
             for {scene, name, _, _} <- lines,
                 do: {"GetSceneItemId", %{sceneName: scene, sourceName: name}}
           ) do
      transforms =
        for {{scene, _name, x, y}, {:ok, %{"sceneItemId" => id}}} <- Enum.zip(lines, ids) do
          {"SetSceneItemTransform",
           %{sceneName: scene, sceneItemId: id, sceneItemTransform: %{positionX: x, positionY: y}}}
        end

      with {:ok, _} <- Obs.batch(transforms), do: :ok
    end
  end

  ## Helpers

  defp do_load_csv(state, path, name) do
    case Results.load(path,
           co_brewer: Application.get_env(:bcoem_obs_awards_presenter, :co_brewer, true)
         ) do
      {:ok, cues} ->
        tables = MapSet.new(cues, & &1.table)
        same_file? = path == state.csv_path
        keep = fn table -> if same_file? and MapSet.member?(tables, table), do: table end

        state = %{
          state
          | csv_path: path,
            csv_name: name || Path.basename(path),
            cues: cues,
            live: keep.(state.live),
            standby: keep.(state.standby) || first_table(cues),
            done: if(same_file?, do: MapSet.intersection(state.done, tables), else: MapSet.new()),
            last_go: if(same_file?, do: state.last_go),
            alert:
              {:info, "Loaded #{length(cues)} categories from #{name || Path.basename(path)}"}
        }

        {{:ok, state}, state}

      {:error, message} ->
        state = %{state | alert: {:error, message}}
        {{:error, message}, state}
    end
  end

  defp first_table([cue | _]), do: cue.table
  defp first_table([]), do: nil

  defp next_table(cues, table) do
    cues |> Enum.drop_while(&(&1.table != table)) |> Enum.at(1) |> then(&(&1 && &1.table))
  end

  defp warnings_alert([]), do: nil
  defp warnings_alert(warnings), do: {:warning, "Loaded, but: " <> Enum.join(warnings, "; ")}

  defp changed(state) do
    broadcast(state)
    {:reply, {:ok, state}, state}
  end

  defp fail(state, message) do
    Logger.warning(message)
    state = %{state | alert: {:error, message}}
    broadcast(state)
    {:reply, {:error, message}, state}
  end

  defp broadcast(state),
    do: Phoenix.PubSub.broadcast(BcoemObsAwardsPresenter.PubSub, @topic, {:show, state})
end
