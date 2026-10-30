defmodule BcoemObsAwardsPresenter.ResultsTest do
  use ExUnit.Case, async: true

  alias BcoemObsAwardsPresenter.Results

  @csv """
  ﻿Table,Name,Category,Subcategory,Style,Place,"Last Name","First Name","Email Address","Entry Name",Club,Co-Brewer
  22,"Table 22 - Spice/Herb/Vegetable Beer",30,B,"Autumn Seasonal Beer",3,Patel,Nina,x@example.com,"That's Right, It's Spiced",,
  6,"Table 6 - Light Hybrid Beer",5,B,Kölsch,2,Fischer,Lena,x@example.com,"Fjord Song (Pronounced ""fyord"")","Riverside Brewers Guild",
  6,"Table 6 - Light Hybrid Beer",5,B,Kölsch,1,Martin,Theo,x@example.com,"Morning Commute","Riverside Brewers Guild","Sam Abbott"
  6,"Table 6 - Light Hybrid Beer",5,B,Kölsch,HM,Park,Mina,x@example.com,"Riverbank",,
  """

  test "orders cues by table and strips the table prefix" do
    assert {:ok, [six, twenty_two]} = Results.parse(@csv)
    assert {six.table, six.category} == {6, "Light Hybrid Beer"}
    assert {twenty_two.table, twenty_two.category} == {22, "Spice/Herb/Vegetable Beer"}
  end

  test "keeps apostrophes, commas and quotes intact" do
    {:ok, [six, twenty_two]} = Results.parse(@csv)

    assert twenty_two.places[3].entry == "That's Right, It's Spiced"
    assert twenty_two.places[3].club == ""
    assert six.places[2].entry == ~s[Fjord Song (Pronounced "fyord")]
  end

  test "only keeps places 1-3 and optionally adds the co-brewer" do
    {:ok, [six, _]} = Results.parse(@csv)
    assert Map.keys(six.places) |> Enum.sort() == [1, 2]
    assert six.places[1].brewer == "Theo Martin & Sam Abbott"

    {:ok, [six, _]} = Results.parse(@csv, co_brewer: false)
    assert six.places[1].brewer == "Theo Martin"
  end

  test "reports missing columns" do
    assert {:error, message} = Results.parse("Table,Name\n1,x\n")
    assert message =~ "Winners: Limited Data"
    assert message =~ "missing these columns: Place"
  end
end
