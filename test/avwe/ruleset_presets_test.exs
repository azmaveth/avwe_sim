defmodule Avwe.RulesetPresetsTest do
  @moduledoc """
  What a world's definition may say of its rules: a preset of a package, rules added
  to it and left out of it, or a list of rules (`Avwe.Ruleset.resolve/1`). The
  packages are in the application's configuration, which is global, so this module
  is not async and puts the configuration back.
  """

  use ExUnit.Case, async: false

  import Avwe.Test.RuleMaker

  alias Avwe.Ruleset

  defsystem(Generator, "station.power/step")
  defsystem(Scrubber, "station.air/step")

  defrule(RPower, "station.power",
    provides: [:power],
    owns: [{:env, :power_w}],
    systems: [{"step", Generator}]
  )

  defrule(RAir, "station.air",
    requires: [:power],
    owns: [{:env, :oxygen}],
    systems: [{"step", Scrubber}]
  )

  defrule(RLights, "station.lights", uses: [:power])

  defmodule Package do
    @moduledoc false
    @behaviour Avwe.RulePackage

    @impl Avwe.RulePackage
    def rules,
      do: [
        Avwe.RulesetPresetsTest.RPower,
        Avwe.RulesetPresetsTest.RAir,
        Avwe.RulesetPresetsTest.RLights
      ]

    @impl Avwe.RulePackage
    def presets, do: %{"station" => ["station.power", "station.air", "station.lights"]}
  end

  setup do
    keys = [:rule_packages, :default_preset]
    previous = for key <- keys, do: {key, Application.fetch_env(:avwe_sim, key)}

    Application.put_env(:avwe_sim, :rule_packages, [Package])
    Application.delete_env(:avwe_sim, :default_preset)

    on_exit(fn ->
      for {key, saved} <- previous do
        case saved do
          {:ok, value} -> Application.put_env(:avwe_sim, key, value)
          :error -> Application.delete_env(:avwe_sim, key)
        end
      end
    end)
  end

  defp ids(plan), do: Enum.map(plan.systems, & &1.id)

  test "a definition that says nothing runs the engine's own rule alone, until a default preset is named" do
    assert Ruleset.resolve(nil) == {:ok, [Avwe.Rules.Sim]}

    Application.put_env(:avwe_sim, :default_preset, "station")

    assert {:ok, modules} = Ruleset.resolve(nil)

    assert Enum.map(modules, & &1.id()) == [
             "sim",
             "station.air",
             "station.lights",
             "station.power"
           ]
  end

  test "a preset is the rules it names, and the engine's own" do
    assert {:ok, plan} = Ruleset.plan_for(%{preset: "station"})

    assert ids(plan) == ["sim/miracles", "station.air/step", "station.power/step"]
    assert plan.providers[:power] == ["station.power"]
  end

  test "a rule left out is left out, and what needed it is refused, in words, with who would provide it" do
    assert {:ok, plan} = Ruleset.plan_for(%{preset: "station", without: ["station.lights"]})
    assert "station.air/step" in ids(plan)

    assert Ruleset.plan_for(%{preset: "station", without: ["station.power"]}) ==
             {:error,
              [
                "station.air needs :power, which no rule in this ruleset provides " <>
                  "(station.power does)"
              ]}
  end

  test "a rule named that no package ships is refused, wherever it is named" do
    for spec <- [
          %{preset: "station", with: ["station.fyre"]},
          %{preset: "station", without: ["station.fyre"]},
          %{rules: ["station.power", "station.fyre"]}
        ] do
      assert {:error, [message]} = Ruleset.resolve(spec)
      assert message =~ ~s(no rule has the id "station.fyre")
      assert message =~ ~s("station.power")
    end
  end

  test "a preset that no package names is refused, naming those that exist" do
    assert {:error, [message]} = Ruleset.resolve(%{preset: "medieval"})

    assert message =~ ~s(no ruleset preset is named "medieval")
    assert message =~ ~s("station")
  end

  test "the engine's own rule cannot be left out" do
    assert Ruleset.resolve(%{preset: "station", without: ["sim"]}) ==
             {:error, ["sim always runs and cannot be left out"]}
  end

  test "a rule added and left out at once is refused, not guessed" do
    spec = %{preset: "station", with: ["station.lights"], without: ["station.lights"]}

    assert Ruleset.resolve(spec) == {:error, ["station.lights is both added and left out"]}
  end

  test "a rule added that the preset has, or listed twice, is still one rule" do
    {:ok, plain} = Ruleset.plan_for(%{preset: "station"})
    {:ok, added} = Ruleset.plan_for(%{preset: "station", with: ["station.power"]})
    {:ok, listed} = Ruleset.plan_for(%{rules: ["station.power", "station.power", "station.air"]})

    assert ids(added) == ids(plain)
    assert Enum.sort(ids(listed)) == Enum.sort(ids(plain))
  end

  test "a ruleset may be given as a keyword list, as a definition keeps it" do
    assert Ruleset.plan_for(preset: "station", without: ["station.lights"]) ==
             Ruleset.plan_for(%{preset: "station", without: ["station.lights"]})
  end

  test "a ruleset that is neither a preset nor a list of rules is refused" do
    assert Ruleset.resolve(%{with: ["station.power"]}) ==
             {:error,
              ["a ruleset is a preset (with rules added and left out) or a list of rules"]}
  end
end
