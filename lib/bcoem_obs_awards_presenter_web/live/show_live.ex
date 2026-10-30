defmodule BcoemObsAwardsPresenterWeb.ShowLive do
  @moduledoc """
  The control page: a QLab-style cue list with a GO button.

  Keyboard: Space = GO, ↑/↓ = move standby, Esc = hide all places.

  The winners CSV can be dropped anywhere on the page or picked with the
  file chooser. Browsers don't reveal a file's path, so the upload is saved
  to the same file every time; Show sees each upload as the same file and
  keeps the show's place, even when the browser renamed a re-download.
  """
  use BcoemObsAwardsPresenterWeb, :live_view

  alias BcoemObsAwardsPresenter.{Obs, Settings, Show}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Show.subscribe()
    show = Show.get()

    {:ok,
     socket
     |> assign(page_title: "Control", places: Show.overlay()[:places])
     |> assign_obs_settings()
     |> allow_upload(:csv,
       accept: ~w(.csv),
       max_entries: 1,
       auto_upload: true,
       progress: &handle_progress/3
     )
     |> assign_show(show)}
  end

  @impl true
  def handle_info({:show, show}, socket), do: {:noreply, assign_show(socket, show)}

  @impl true
  def handle_event("go", _params, socket), do: run(socket, &Show.go/0)
  def handle_event("standby_next", _params, socket), do: run(socket, fn -> Show.step(:next) end)
  def handle_event("standby_prev", _params, socket), do: run(socket, fn -> Show.step(:prev) end)
  def handle_event("hide_all", _params, socket), do: run(socket, &Show.hide_all/0)
  def handle_event("check_setup", _params, socket), do: run(socket, &Show.check_setup/0)
  def handle_event("build_missing", _params, socket), do: run(socket, &Show.build_missing/0)
  def handle_event("dismiss_alert", _params, socket), do: run(socket, &Show.dismiss_alert/0)

  def handle_event("standby", %{"table" => table}, socket) do
    run(socket, fn -> Show.standby(String.to_integer(table)) end)
  end

  def handle_event("save_obs", %{"url" => url, "password" => password}, socket) do
    Settings.save_obs(url, password)
    {:noreply, socket |> reconnect_obs() |> assign_obs_settings()}
  end

  def handle_event("forget_obs_password", _params, socket) do
    Settings.forget_obs_password()
    {:noreply, socket |> reconnect_obs() |> assign_obs_settings()}
  end

  # Uploads start on their own (auto_upload); these just satisfy the form.
  def handle_event("validate_csv", _params, socket), do: {:noreply, socket}
  def handle_event("save_csv", _params, socket), do: {:noreply, socket}

  defp reconnect_obs(socket) do
    case Obs.reconnect() do
      :ok -> put_flash(socket, :info, "Saved. Reconnecting to OBS…")
      {:error, _} -> put_flash(socket, :error, "Saved, but the OBS client isn't running")
    end
  end

  defp assign_obs_settings(socket) do
    info = Settings.obs_info()
    assign(socket, obs_info: info, obs_form: to_form(%{"url" => info.url, "password" => ""}))
  end

  defp handle_progress(:csv, %{done?: true} = entry, socket) do
    dest = upload_path()

    consume_uploaded_entry(socket, entry, fn %{path: tmp} ->
      File.mkdir_p!(Path.dirname(dest))
      File.cp!(tmp, dest)
      {:ok, dest}
    end)

    run(socket, fn -> Show.load_csv(dest, entry.client_name) end)
  end

  defp handle_progress(:csv, _entry, socket), do: {:noreply, socket}

  # Outside the repo: the export holds winners' contact details.
  defp upload_path,
    do: Path.join([System.tmp_dir!(), "bcoem_obs_awards_presenter", "winners.csv"])

  # Results also arrive via PubSub; applying the reply directly keeps this
  # page snappy and correct even if the broadcast is still in flight.
  defp run(socket, fun) do
    case fun.() do
      {:ok, show} -> {:noreply, assign_show(socket, show)}
      {:error, _message} -> {:noreply, assign_show(socket, Show.get())}
    end
  end

  defp assign_show(socket, show) do
    assign(socket,
      show: show,
      live_cue: show.live && Show.cue(show, show.live),
      standby_cue: show.standby && Show.cue(show, show.standby)
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div
        id="csv-drop"
        phx-drop-target={@uploads.csv.ref}
        class="min-h-[calc(100vh-10rem)] space-y-6"
      >
        <div class="pointer-events-none fixed inset-0 z-50 hidden items-center justify-center border-4 border-dashed border-primary bg-base-100/80 phx-drop-target-active:flex">
          <div class="text-2xl font-semibold">Drop the winners CSV to load it</div>
        </div>
        <div id="show-keys" phx-hook=".ShowKeys" class="hidden"></div>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".ShowKeys">
          export default {
            mounted() {
              const keys = {" ": "go", ArrowDown: "standby_next", ArrowUp: "standby_prev", Escape: "hide_all"}
              this.onKey = (e) => {
                const event = keys[e.key]
                if (!event || e.repeat || e.metaKey || e.ctrlKey || e.target.closest("input, textarea, select")) return
                // Also stops Space from "clicking" whichever button has focus.
                e.preventDefault()
                this.pushEvent(event, {})
              }
              window.addEventListener("keydown", this.onKey)
            },
            destroyed() { window.removeEventListener("keydown", this.onKey) }
          }
        </script>

        <div class="flex flex-wrap items-center gap-3">
          <.obs_badge status={@show.obs} detail={@show.obs_detail} />
          <form
            id="csv-form"
            phx-change="validate_csv"
            phx-submit="save_csv"
            class="flex-1 min-w-80"
          >
            <label
              for={@uploads.csv.ref}
              class="flex cursor-pointer items-center gap-3 rounded-box border-2 border-dashed border-base-300 px-4 py-2 transition-colors hover:border-primary hover:bg-base-200"
            >
              <.icon name="hero-arrow-up-tray" class="size-5 shrink-0 opacity-70" />
              <span :if={@show.csv_name} class="truncate">
                <span class="font-mono">{@show.csv_name}</span>
                <span class="text-sm opacity-60">· drop or choose a new export to reload</span>
              </span>
              <span :if={!@show.csv_name} class="opacity-80">
                Drop the winners CSV anywhere, or click to choose it
              </span>
              <span
                :for={entry <- @uploads.csv.entries}
                :if={!entry.done?}
                class="ml-auto text-sm tabular-nums opacity-60"
              >
                {entry.progress}%
              </span>
            </label>
            <.live_file_input upload={@uploads.csv} class="sr-only" />
            <button
              :if={@show.cues != []}
              id="csv-help-toggle"
              type="button"
              class="link link-hover mt-1 inline-flex items-center gap-1 text-xs opacity-70"
              phx-click={JS.toggle(to: "#csv-help-panel")}
            >
              <.icon name="hero-question-mark-circle" class="size-4" />
              Where does this file come from?
            </button>
            <p :for={err <- upload_errors(@uploads.csv)} class="mt-1 text-sm text-error">
              {upload_error(err)}
            </p>
            <%= for entry <- @uploads.csv.entries, err <- upload_errors(@uploads.csv, entry) do %>
              <p class="mt-1 text-sm text-error">{entry.client_name}: {upload_error(err)}</p>
            <% end %>
          </form>
        </div>

        <.csv_help :if={@show.cues != []} id="csv-help-panel" class="hidden" />

        <div :if={@show.alert} role="alert" class={["alert", alert_class(@show.alert)]}>
          <span>{elem(@show.alert, 1)}</span>
          <button class="btn btn-ghost btn-xs" phx-click="dismiss_alert">Dismiss</button>
        </div>

        <div class="grid gap-4 md:grid-cols-2">
          <section class="card bg-base-200 border-2 border-success/60">
            <div class="card-body gap-3">
              <div class="text-xs font-bold tracking-widest text-success">LIVE</div>
              <.cue_title cue={@live_cue} empty="Nothing loaded yet" />
              <div class="flex flex-wrap items-center gap-2">
                <span
                  :for={{place, _source} <- @places}
                  class={[
                    "badge badge-lg",
                    if(@show.revealed[place], do: "badge-success", else: "badge-ghost")
                  ]}
                >
                  {ordinal(place)} {if @show.revealed[place], do: "shown", else: "hidden"}
                </span>
                <button class="btn btn-sm btn-outline ml-auto" phx-click="hide_all">
                  Hide all <kbd class="kbd kbd-xs">Esc</kbd>
                </button>
              </div>
            </div>
          </section>

          <section class="card bg-base-200 border-2 border-warning/60">
            <div class="card-body gap-3">
              <div class="text-xs font-bold tracking-widest text-warning">STANDBY</div>
              <.cue_title cue={@standby_cue} empty="End of list" />
              <div class="flex items-center gap-2">
                <button class="btn btn-sm" phx-click="standby_prev" aria-label="Previous cue">↑</button>
                <button class="btn btn-sm" phx-click="standby_next" aria-label="Next cue">↓</button>
                <button
                  id="go"
                  class="btn btn-success btn-lg ml-auto px-10 text-xl"
                  phx-click="go"
                  disabled={is_nil(@standby_cue) or @show.obs != :connected}
                >
                  GO <kbd class="kbd kbd-sm">Space</kbd>
                </button>
              </div>
            </div>
          </section>
        </div>

        <section :if={@standby_cue}>
          <h2 class="text-sm font-semibold opacity-70 mb-2">
            Up next: check names before GO (shown in reveal order)
          </h2>
          <div class="grid gap-3 md:grid-cols-3">
            <div :for={{place, _source} <- @places} class="card card-border bg-base-100">
              <div class="card-body p-4 gap-1">
                <div class="text-xs font-bold opacity-60">{ordinal(place)} PLACE</div>
                <%= if entry = @standby_cue.places[place] do %>
                  <div class="font-semibold">{entry.brewer}</div>
                  <div class="italic">{entry.entry}</div>
                  <div class="text-sm opacity-80">{entry.club}</div>
                  <div class="text-xs opacity-60">{entry.style}</div>
                <% else %>
                  <div class="text-warning">No {ordinal(place)} place awarded</div>
                <% end %>
              </div>
            </div>
          </div>
        </section>

        <section class="overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr>
                <th class="w-24"></th>
                <th>Table</th>
                <th>Category</th>
                <th :for={{place, _source} <- @places}>{ordinal(place)}</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={cue <- @show.cues}
                id={"cue-#{cue.table}"}
                phx-click="standby"
                phx-value-table={cue.table}
                class={["cursor-pointer hover:bg-base-200", row_class(@show, cue)]}
              >
                <td class="font-bold text-xs">{status_label(@show, cue)}</td>
                <td class="tabular-nums">{cue.table}</td>
                <td class="font-medium">{cue.category}</td>
                <td :for={{place, _source} <- @places} class="text-sm">
                  {(cue.places[place] && cue.places[place].brewer) || "—"}
                </td>
              </tr>
            </tbody>
          </table>
          <.csv_help :if={@show.cues == []} id="csv-help" class="mt-4" />
        </section>

        <details
          id="setup"
          class="collapse collapse-arrow bg-base-200"
          open={@show.obs == :disconnected}
        >
          <summary class="collapse-title font-semibold">
            OBS connection, setup and Stream Deck
          </summary>
          <div class="collapse-content space-y-4">
            <.form
              for={@obs_form}
              id="obs-settings-form"
              phx-submit="save_obs"
              class="grid items-end gap-x-3 sm:grid-cols-[1fr_1fr_auto]"
            >
              <.input
                field={@obs_form[:url]}
                label="OBS WebSocket address"
                class="input input-sm w-full font-mono"
              />
              <.input
                field={@obs_form[:password]}
                type="password"
                label="Password"
                placeholder={password_placeholder(@obs_info.password_source)}
                autocomplete="off"
                class="input input-sm w-full"
              />
              <button class="btn btn-sm btn-primary mb-2">Save and reconnect</button>
            </.form>
            <p class="-mt-2 text-xs opacity-70">
              In OBS: Tools → WebSocket Server Settings → Show Connect Info.
              <button
                :if={@obs_info.password_source == :saved}
                id="forget-obs-password"
                type="button"
                class="link"
                phx-click="forget_obs_password"
              >
                Forget the saved password
              </button>
            </p>
            <div class="flex gap-2">
              <button class="btn btn-sm" phx-click="check_setup">Check OBS setup</button>
              <button
                :if={@show.setup && Enum.any?(@show.setup, fn {_, _, ok} -> !ok end)}
                class="btn btn-sm btn-primary"
                phx-click="build_missing"
              >
                Create missing sources
              </button>
            </div>
            <ul :if={@show.setup} class="text-sm space-y-1">
              <li :for={{kind, name, ok} <- @show.setup}>
                <span class={if ok, do: "text-success", else: "text-error"}>{if ok, do: "✓", else: "✗"}</span>
                <span class="font-mono">{name}</span> <span class="opacity-60">({kind})</span>
              </li>
            </ul>
            <div class="text-sm space-y-1">
              <p>
                Stream Deck: use the <strong>Website</strong>
                action with <em>GET request in background</em>
                checked:
              </p>
              <ul class="font-mono">
                <li :for={path <- ~w(go next prev hide-all)}>
                  {BcoemObsAwardsPresenterWeb.Endpoint.url()}/api/{path}
                </li>
              </ul>
            </div>
          </div>
        </details>
      </div>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :class, :string, default: nil

  # Where the winners CSV comes from: shown in place of the empty cue list,
  # and behind a link once a file is loaded.
  defp csv_help(assigns) do
    ~H"""
    <div id={@id} class={["card card-border bg-base-100", @class]}>
      <div class="card-body gap-3 p-5">
        <h2 class="card-title text-base">
          <.icon name="hero-document-arrow-down" class="size-5 opacity-70" />
          Getting the winners CSV from BCOE&M
        </h2>
        <ol class="list-decimal space-y-2 pl-5 text-sm">
          <li>
            Enter every table's places in BCOE&M first: the export only has the
            entries that placed.
          </li>
          <li>
            In BCOE&M, go to <span class="font-semibold">Admin Dashboard</span>
            → <span class="font-semibold">Data Exports</span>
            → <span class="font-semibold">Participant Data (CSV)</span>
            → <span class="font-semibold">Winners: Limited Data</span>. It downloads a CSV.
          </li>
          <li>
            Drag that file onto this page, or click the box at the top to choose it.
            The cue list fills with one row per table.
          </li>
        </ol>
        <ul class="space-y-1 text-xs opacity-70">
          <li>
            Fixed a result in BCOE&M? Download the export again and drop it here. The show keeps its place.
          </li>
          <li>
            Only 1st to 3rd place are shown. Best of Show isn't in this export; its slides are edited in OBS.
          </li>
          <li>
            The export includes winners' email and home addresses. This app keeps its copy in the
            system's temporary folder; don't share the file or commit it anywhere.
          </li>
        </ul>
      </div>
    </div>
    """
  end

  attr :cue, :any, required: true
  attr :empty, :string, required: true

  defp cue_title(%{cue: nil} = assigns) do
    ~H"""
    <div class="text-2xl font-semibold opacity-40">{@empty}</div>
    """
  end

  defp cue_title(assigns) do
    ~H"""
    <div>
      <div class="text-sm opacity-60">Table {@cue.table}</div>
      <div class="text-2xl font-semibold">{@cue.category}</div>
    </div>
    """
  end

  attr :status, :atom, required: true
  attr :detail, :string, default: nil

  defp obs_badge(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <span class={[
        "badge",
        case @status do
          :connected -> "badge-success"
          :connecting -> "badge-warning"
          :disconnected -> "badge-error"
        end
      ]}>
        OBS {@status}
      </span>
      <span :if={@detail && @status != :connected} class="text-xs opacity-70">{@detail}</span>
    </div>
    """
  end

  defp status_label(show, cue) do
    cond do
      cue.table == show.live -> "● LIVE"
      cue.table == show.standby -> "▶ STANDBY"
      MapSet.member?(show.done, cue.table) -> "✓ done"
      true -> ""
    end
  end

  defp row_class(show, cue) do
    cond do
      cue.table == show.live -> "bg-success/20 text-success"
      cue.table == show.standby -> "bg-warning/20"
      MapSet.member?(show.done, cue.table) -> "opacity-50"
      true -> nil
    end
  end

  defp password_placeholder(:saved), do: "Saved (leave blank to keep it)"
  defp password_placeholder(:env), do: "From OBS_PASSWORD"
  defp password_placeholder(nil), do: "None"

  defp upload_error(:not_accepted), do: "that isn't a .csv file"
  defp upload_error(:too_large), do: "the file is too large"
  defp upload_error(:too_many_files), do: "drop one file at a time"
  defp upload_error(err), do: to_string(err)

  defp alert_class({:error, _}), do: "alert-error"
  defp alert_class({:warning, _}), do: "alert-warning"
  defp alert_class({:info, _}), do: "alert-info"

  defp ordinal(1), do: "1st"
  defp ordinal(2), do: "2nd"
  defp ordinal(3), do: "3rd"
  defp ordinal(n), do: "#{n}th"
end
