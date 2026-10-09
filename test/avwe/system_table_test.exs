defmodule Avwe.SystemTableTest do
  @moduledoc """
  The table of system ids is global to the VM. The tests that change what an id
  means run by themselves (a module that is not async runs when the async ones are
  done) and put it back.
  """

  use ExUnit.Case, async: false

  import Avwe.Test.RuleMaker

  alias Avwe.SystemTable

  @pump "test.table.pump/step"

  defsystem(Pump, "test.table.pump/step")
  defsystem(Valve, "test.table.valve/step")
  defrule(RPump, "test.table.pump", systems: [{"step", Pump}])

  defmodule Package do
    @moduledoc false
    @behaviour Avwe.RulePackage

    @impl Avwe.RulePackage
    def rules, do: [Avwe.SystemTableTest.RPump]

    @impl Avwe.RulePackage
    def presets, do: %{}
  end

  setup do
    previous = Application.get_env(:avwe_sim, :rule_packages)
    Application.put_env(:avwe_sim, :rule_packages, [Package])

    on_exit(fn ->
      if previous,
        do: Application.put_env(:avwe_sim, :rule_packages, previous),
        else: Application.delete_env(:avwe_sim, :rule_packages)

      for id <- [@pump, "test.table.fresh/step"], do: :persistent_term.erase({SystemTable, id})
    end)
  end

  test "an id of a rule a package ships is found even when the table was never told of it" do
    :persistent_term.erase({SystemTable, @pump})

    assert SystemTable.fetch(@pump) == {:ok, Pump}
    assert SystemTable.missing([@pump, "test.table.never/step"]) == ["test.table.never/step"]
  end

  test "looking for an id nothing runs does not undo a move of one that something does" do
    :ok = SystemTable.put(@pump, Valve)

    assert SystemTable.fetch("test.table.nobody/step") == :error
    assert SystemTable.fetch(@pump) == {:ok, Valve}
  end

  test "put_new says that a module runs a system only when none does" do
    :ok = SystemTable.put_new("test.table.fresh/step", Pump)
    :ok = SystemTable.put_new("test.table.fresh/step", Valve)

    assert SystemTable.fetch("test.table.fresh/step") == {:ok, Pump}
  end
end
