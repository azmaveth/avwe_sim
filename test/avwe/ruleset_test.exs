defmodule Avwe.RulesetTest do
  @moduledoc """
  A world's rules and the check on them (`Avwe.Ruleset`): small rules made for
  each way a set can be wrong.
  """

  use ExUnit.Case, async: true

  import Avwe.Test.RuleMaker

  alias Avwe.{Ruleset, SystemTable}

  # Systems and rules made for the tests. Ids are all `test.ruleset.*`.
  defsystem(A1, "test.ruleset.a/step")
  defsystem(B, "test.ruleset.b/step")
  defsystem(D, "test.ruleset.zz_early/step")
  defsystem(E, "test.ruleset.first/one")
  defsystem(F, "test.ruleset.first/two")
  defsystem(Zebra, "test.ruleset.backwards/zebra")
  defsystem(Aardvark, "test.ruleset.backwards/aardvark")
  defsystem(G, "test.ruleset.late/step")
  defsystem(H, "test.ruleset.after_ping/step")
  defsystem(Y, "test.ruleset.ties_y/step")
  defsystem(Z, "test.ruleset.ties_z/step")
  defsystem(LX, "test.ruleset.loop_x/step")
  defsystem(LW, "test.ruleset.loop_w/step")
  defsystem(T1, "test.ruleset.twice/step")
  defsystem(O1, "test.ruleset.options/step")
  defsystem(W1, "test.ruleset.waits/step")

  defrule(RA, "test.ruleset.a",
    owns: [{:component, :shared}],
    provides: [:ping],
    systems: [{"step", A1}]
  )

  defrule(RB, "test.ruleset.b", owns: [{:component, :shared}, {:env, :own}])
  defrule(RC, "test.ruleset.c", conflicts: ["test.ruleset.d"])
  defrule(RD, "test.ruleset.d")
  defrule(RNeeds, "test.ruleset.needs", requires: [:ping], uses: [:pong])
  defrule(RWrongId, "test.ruleset.wrongid", systems: [{"step", B}])
  defrule(RFirst, "test.ruleset.first", systems: [{"one", E}, {"two", F}])

  # Listed in the opposite order to the alphabet of its ids.
  defrule(RBackwards, "test.ruleset.backwards",
    systems: [{"zebra", Zebra}, {"aardvark", Aardvark}]
  )

  defrule(RLate, "test.ruleset.late",
    runs_after: ["test.ruleset.first/two"],
    systems: [{"step", G}]
  )

  defrule(REarly, "test.ruleset.zz_early",
    runs_before: ["test.ruleset.first"],
    systems: [{"step", D}]
  )

  defrule(RTiesZ, "test.ruleset.ties_z", systems: [{"step", Z}])
  defrule(RTiesY, "test.ruleset.ties_y", systems: [{"step", Y}])

  defrule(RLoopX, "test.ruleset.loop_x",
    runs_after: ["test.ruleset.loop_w"],
    systems: [{"step", LX}]
  )

  defrule(RLoopW, "test.ruleset.loop_w",
    runs_after: ["test.ruleset.loop_x"],
    systems: [{"step", LW}]
  )

  # Waits on a rule that is in a loop, without being in it.
  defrule(RWaits, "test.ruleset.waits",
    runs_after: ["test.ruleset.loop_x"],
    systems: [{"step", W1}]
  )

  defrule(RTwice, "test.ruleset.twice", systems: [{"step", T1}, {"step", T1}])

  defrule(RBadPeriod, "test.ruleset.options", systems: [{"step", O1, every: 0}])
  defrule(RFloatPeriod, "test.ruleset.options", systems: [{"step", O1, every: 60.5}])
  defrule(RMisspelt, "test.ruleset.options", systems: [{"step", O1, evry: 60}])
  defrule(RPeriod, "test.ruleset.options", systems: [{"step", O1, every: 300}])

  defrule(RTypo, "test.ruleset.typo",
    runs_after: ["test.ruleset.nowhere/step", :nothing_provides_this]
  )

  defrule(RAfterPing, "test.ruleset.after_ping",
    runs_after: [:ping],
    systems: [{"step", H}]
  )

  defp ids(plan), do: Enum.map(plan.systems, & &1.id)

  defp problems(modules, opts \\ []) do
    assert {:error, problems} = Ruleset.plan(modules, opts)
    problems
  end

  describe "registering a plan" do
    test "lets a region run its systems by id, which the table did not know before" do
      {:ok, plan} = Ruleset.plan([RA])

      assert SystemTable.fetch("test.ruleset.a/step") == :error
      :ok = Ruleset.register(plan)

      assert SystemTable.fetch("test.ruleset.a/step") == {:ok, A1}
    end
  end

  describe "refusing a ruleset, in words" do
    test "all the problems at once, sorted" do
      problems = problems([RA, RB, RC, RD, RNeeds, RWrongId])

      assert problems == Enum.sort(problems)
      assert length(problems) == 3
    end

    test "two rules that own one key" do
      assert problems([RA, RB]) == [
               "the component shared is owned by both test.ruleset.a and test.ruleset.b; a rule " <>
                 "that wants to affect another's state feeds it through entities of its own or " <>
                 "through events"
             ]
    end

    test "rules that conflict" do
      assert problems([RC, RD]) == ["test.ruleset.c cannot run beside test.ruleset.d"]
      assert {:ok, _plan} = Ruleset.plan([RC])
    end

    test "a rule listed twice" do
      assert problems([RA, RA]) |> Enum.member?("the rule test.ruleset.a is listed twice")
    end

    test "a requirement that is met, and one that is only used" do
      assert {:ok, _plan} = Ruleset.plan([RA, RNeeds])

      assert problems([RNeeds], known: []) == [
               "test.ruleset.needs needs :ping, which no rule in this ruleset provides"
             ]
    end

    test "the hint names every rule that would provide it" do
      known = Enum.map([RA, RB], &Avwe.Rule.manifest/1)
      extra = %{Avwe.Rule.manifest(RB) | id: "test.ruleset.b2", provides: [:ping]}

      assert problems([RNeeds], known: known) == [
               "test.ruleset.needs needs :ping, which no rule in this ruleset provides " <>
                 "(test.ruleset.a does)"
             ]

      assert problems([RNeeds], known: [extra | known]) == [
               "test.ruleset.needs needs :ping, which no rule in this ruleset provides " <>
                 "(test.ruleset.a and test.ruleset.b2 do)"
             ]
    end

    test "a system module whose id is not its rule's" do
      assert problems([RWrongId]) == [
               "test.ruleset.wrongid lists its system step as Avwe.RulesetTest.B, " <>
                 "whose id is test.ruleset.b/step and not test.ruleset.wrongid/step"
             ]
    end
  end

  describe "what a rule says of its systems" do
    test "a system listed twice is a clash, not a loop" do
      assert problems([RTwice]) == ["test.ruleset.twice lists a system named step twice"]
    end

    test "a period is a whole number of seconds above 0" do
      assert problems([RBadPeriod]) == [
               "test.ruleset.options lists its system step with every: 0, which is not a " <>
                 "whole number of seconds above 0"
             ]

      assert problems([RFloatPeriod]) == [
               "test.ruleset.options lists its system step with every: 60.5, which is not a " <>
                 "whole number of seconds above 0"
             ]

      assert {:ok, plan} = Ruleset.plan([RPeriod])
      assert Ruleset.systems(plan) == [{"test.ruleset.options/step", [every: 300]}]
    end

    test "an option that a system does not have is refused, not ignored" do
      assert problems([RMisspelt]) == [
               "test.ruleset.options lists its system step with the option :evry, which a " <>
                 "system does not have (it has :every, :runs_after, :runs_before)"
             ]
    end
  end

  describe "order" do
    test "a rule's own systems run as it lists them, and others as they say" do
      {:ok, backwards} = Ruleset.plan([RBackwards])

      assert ids(backwards) == [
               "test.ruleset.backwards/zebra",
               "test.ruleset.backwards/aardvark"
             ]

      {:ok, plan} = Ruleset.plan([RFirst, RLate, REarly])

      assert ids(plan) == [
               "test.ruleset.zz_early/step",
               "test.ruleset.first/one",
               "test.ruleset.first/two",
               "test.ruleset.late/step"
             ]
    end

    test "what no constraint settles is sorted by id, whatever order the rules were given in" do
      {:ok, plan} = Ruleset.plan([RTiesZ, RTiesY])
      {:ok, reversed} = Ruleset.plan([RTiesY, RTiesZ])

      assert ids(plan) == ["test.ruleset.ties_y/step", "test.ruleset.ties_z/step"]
      assert ids(reversed) == ids(plan)
    end

    test "a capability is a constraint on the systems of the rules that provide it" do
      {:ok, plan} = Ruleset.plan([RAfterPing, RA])

      assert ids(plan) == ["test.ruleset.a/step", "test.ruleset.after_ping/step"]
    end

    test "a constraint on a rule the ruleset does not have changes nothing" do
      known = [Avwe.Rule.manifest(RA)]

      assert {:ok, plan} = Ruleset.plan([RAfterPing], known: known)
      assert ids(plan) == ["test.ruleset.after_ping/step"]
    end

    test "constraints that cannot all be met" do
      assert problems([RLoopX, RLoopW]) == [
               "these systems each wait for another to run first, so none can: " <>
                 "test.ruleset.loop_w/step, test.ruleset.loop_x/step"
             ]
    end

    test "a system that only waits on a loop is not named as part of it" do
      assert problems([RLoopX, RLoopW, RWaits]) == [
               "these systems each wait for another to run first, so none can: " <>
                 "test.ruleset.loop_w/step, test.ruleset.loop_x/step"
             ]
    end

    test "a constraint that names nothing at all is a slip and not a rule left out" do
      assert problems([RTypo]) == [
               ~s(test.ruleset.typo must run in order with "test.ruleset.nowhere/step", which is no rule, system or capability),
               ~s(test.ruleset.typo must run in order with :nothing_provides_this, which is no rule, system or capability)
             ]
    end
  end
end
