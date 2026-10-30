defmodule BcoemObsAwardsPresenter.Results do
  @moduledoc """
  Parses the competition's winners CSV export into an ordered list of cues,
  one per table, each holding up to three placing entries.
  """

  NimbleCSV.define(BcoemObsAwardsPresenter.Results.CSV, separator: ",", escape: "\"")

  alias BcoemObsAwardsPresenter.Results.CSV

  defmodule Entry do
    @moduledoc "A single placing entry."
    defstruct [:place, :brewer, :entry, :club, :style]
  end

  defmodule Cue do
    @moduledoc "One table's results: what a single GO loads into OBS."
    defstruct [:table, :name, :category, places: %{}]
  end

  @required_headers ["Table", "Name", "Place", "First Name", "Last Name", "Entry Name", "Club"]

  @doc """
  Reads and parses the CSV at `path`.

  Options:

    * `:co_brewer` - append the co-brewer to the brewer line (default `true`)
  """
  def load(path, opts \\ []) do
    case File.read(Path.expand(path)) do
      {:ok, contents} -> parse(contents, opts)
      {:error, reason} -> {:error, "Could not read #{path}: #{:file.format_error(reason)}"}
    end
  end

  def parse(contents, opts \\ []) do
    [header | rows] =
      contents
      |> String.trim_leading("﻿")
      |> CSV.parse_string(skip_headers: false)

    case @required_headers -- header do
      [] ->
        cues =
          rows
          |> Enum.map(&(header |> Enum.zip(&1) |> Map.new()))
          |> Enum.flat_map(&to_entry(&1, opts))
          |> Enum.group_by(fn {table, _name, _entry} -> table end)
          |> Enum.map(&to_cue/1)
          |> Enum.sort_by(& &1.table)

        {:ok, cues}

      missing ->
        {:error,
         "This doesn't look like BCOE&M's \"Winners: Limited Data\" export. " <>
           "It's missing these columns: #{Enum.join(missing, ", ")}"}
    end
  end

  defp to_entry(row, opts) do
    with {table, ""} <- Integer.parse(row["Table"]),
         {place, ""} when place in 1..3 <- Integer.parse(row["Place"]) do
      entry = %Entry{
        place: place,
        brewer: brewer(row, Keyword.get(opts, :co_brewer, true)),
        entry: clean(row["Entry Name"]),
        club: clean(row["Club"]),
        style: clean(row["Style"])
      }

      [{table, clean(row["Name"]), entry}]
    else
      _ -> []
    end
  end

  defp to_cue({table, [{_, name, _} | _] = rows}) do
    places =
      Enum.reduce(rows, %{}, fn {_, _, entry}, acc -> Map.put_new(acc, entry.place, entry) end)

    %Cue{table: table, name: name, category: category(name), places: places}
  end

  # "Table 31 - Fresh Hop Beers" -> "Fresh Hop Beers"
  defp category(name) do
    case String.split(name, " - ", parts: 2) do
      [_, category] -> category
      _ -> name
    end
  end

  defp brewer(row, co_brewer?) do
    brewer = clean("#{row["First Name"]} #{row["Last Name"]}")

    case clean(row["Co-Brewer"]) do
      co when co_brewer? and co != "" -> "#{brewer} & #{co}"
      _ -> brewer
    end
  end

  defp clean(nil), do: ""
  defp clean(value), do: String.trim(value)
end
