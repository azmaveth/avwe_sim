defmodule Avwe.WorldSystemIdsTest do
  @moduledoc """
  End to end through a running world and the disk: a saved world names its systems
  by id, so the module behind an id can move, a system's period can change, and a
  world saved with a system that no module runs any more is refused in words.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Avwe.{Region, RegionServer, Store, SystemTable}
  alias Avwe.Test.Worlds

  @moduletag :tmp_dir
  @world :sim_system_ids
  @region {0, 0}

  defmodule Marker do
    @moduledoc false
    @behaviour Avwe.System

    # Writes who ran it into the world's environment.
    @impl Avwe.System
    def system_id, do: "test.e2e.marker/step"

    @impl Avwe.System
    def run(region, _tick), do: {Region.put_env(region, :ran, :marker), []}
  end

  defmodule Successor do
    @moduledoc false
    @behaviour Avwe.System

    # The module the marker moved to.
    @impl Avwe.System
    def system_id, do: "test.e2e.marker/step"

    @impl Avwe.System
    def run(region, _tick), do: {Region.put_env(region, :ran, :successor), []}
  end

  defmodule Tally do
    @moduledoc false
    @behaviour Avwe.System

    # Counts the times it was prepared, which a world must not do twice.
    @impl Avwe.System
    def system_id, do: "test.e2e.tally/step"

    @impl Avwe.System
    def prepare(region),
      do: Region.put_env(region, :prepared, Map.get(region.env, :prepared, 0) + 1)

    @impl Avwe.System
    def run(region, tick), do: {Region.put_env(region, :last, {tick.time, tick.dt}), []}
  end

  defmodule Vanishing do
    @moduledoc false
    @behaviour Avwe.System

    @impl Avwe.System
    def system_id, do: "test.e2e.vanishing/step"

    @impl Avwe.System
    def run(region, _tick), do: {region, []}
  end

  setup do
    on_exit(fn -> Worlds.stop_if_running(@world) end)
  end

  defp start(tmp_dir, systems) do
    Worlds.start(@world, region: Worlds.region(systems: systems), store: store_dir(tmp_dir))
  end

  defp store_dir(tmp_dir), do: Path.join(tmp_dir, "world")

  test "a saved world resumes when the module that runs one of its systems has moved", %{
    tmp_dir: tmp_dir
  } do
    {:ok, _pid} = start(tmp_dir, [Marker])
    Worlds.step(@world, 3)
    assert {:ok, %{env: %{ran: :marker}}} = Worlds.snapshot(@world)
    :ok = Worlds.stop(@world)

    # The system is the same, and lives in another module now.
    :ok = SystemTable.put("test.e2e.marker/step", Successor)

    assert {:ok, _pid} = start(tmp_dir, ["test.e2e.marker/step"])
    assert {:ok, %{step: 3}} = Worlds.snapshot(@world)
    Worlds.step(@world, 2)
    assert {:ok, %{step: 5, env: %{ran: :successor}}} = Worlds.snapshot(@world)
    {:ok, live} = RegionServer.state_hash(@world, @region)
    :ok = Worlds.stop(@world)

    # Nothing was snapshotted for it (the systems are the same ids), and the
    # whole history replays from its first snapshot to the same state.
    {:ok, store} = Store.open(store_dir(tmp_dir), @region)
    assert Store.snapshots(store) == [0]
    assert {:ok, rebuilt} = Store.rebuild_from_start(store)
    :ok = Store.close(store)

    assert Region.state_hash(rebuilt) == live
    assert rebuilt.systems == [{"test.e2e.marker/step", []}]

    SystemTable.put("test.e2e.marker/step", Marker)
  end

  test "a world with a periodic system resumes and replays to the same state", %{
    tmp_dir: tmp_dir
  } do
    # Steps of a minute against a period of 100 s: the periods it is told do not
    # line up with the steps, which the replay must reproduce.
    {:ok, _pid} = start(tmp_dir, [{Tally, every: 100}])
    Worlds.step(@world, 5)
    :ok = Worlds.stop(@world)

    {:ok, _pid} = start(tmp_dir, [{Tally, every: 100}])
    Worlds.step(@world, 4)
    {:ok, live} = RegionServer.state_hash(@world, @region)
    assert {:ok, %{env: %{last: {_time, 100}}}} = Worlds.snapshot(@world)
    :ok = Worlds.stop(@world)

    {:ok, store} = Store.open(store_dir(tmp_dir), @region)
    assert Store.snapshots(store) == [0]
    assert {:ok, rebuilt} = Store.rebuild_from_start(store)
    :ok = Store.close(store)

    assert Region.state_hash(rebuilt) == live
  end

  test "a world resumed with another period for a system is not prepared again, and replays", %{
    tmp_dir: tmp_dir
  } do
    {:ok, _pid} = start(tmp_dir, [Tally])
    Worlds.step(@world, 3)
    assert {:ok, %{env: %{prepared: 1}}} = Worlds.snapshot(@world)
    :ok = Worlds.stop(@world)

    {:ok, _pid} = start(tmp_dir, [{Tally, every: 120}])

    assert {:ok, %{step: 3, env: %{prepared: 1}}} = Worlds.snapshot(@world)

    Worlds.step(@world, 3)
    {:ok, live} = RegionServer.state_hash(@world, @region)
    :ok = Worlds.stop(@world)

    # The log from the change on belongs to the new period, so a snapshot was
    # written at once, and the world comes back from it to the same state.
    {:ok, store} = Store.open(store_dir(tmp_dir), @region)
    assert Store.snapshots(store) == [0, 3]
    assert {:ok, rebuilt} = Store.rebuild(store)
    :ok = Store.close(store)

    assert rebuilt.systems == [{"test.e2e.tally/step", [every: 120]}]
    assert Region.state_hash(rebuilt) == live
  end

  test "a world saved with a system that no module runs is refused, naming it", %{
    tmp_dir: tmp_dir
  } do
    {:ok, _pid} = start(tmp_dir, [Vanishing])
    Worlds.step(@world, 3)
    :ok = Worlds.stop(@world)

    :persistent_term.erase({SystemTable, "test.e2e.vanishing/step"})

    log =
      capture_log(fn ->
        assert {:error,
                {:shutdown,
                 {:failed_to_start_child, _child,
                  {:store, {:unknown_systems, ["test.e2e.vanishing/step"]}}}}} =
                 start(tmp_dir, [])
      end)

    assert log =~
             "the world was saved with systems this build does not have: " <>
               "test.e2e.vanishing/step"

    assert log =~ "delete the world folder #{store_dir(tmp_dir)} to start over"
    assert Avwe.World.whereis(@world) == nil

    SystemTable.put("test.e2e.vanishing/step", Vanishing)
  end
end
