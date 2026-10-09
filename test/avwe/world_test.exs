defmodule Avwe.WorldTest do
  @moduledoc """
  A running world (`Avwe.World`, `Avwe.Clock`, `Avwe.RegionServer`) with a region the
  test made: stepping by hand and by the clock, what a subscriber is told, and what
  the world says of itself.
  """

  use ExUnit.Case, async: false

  alias Avwe.{Calendar, Event, World}
  alias Avwe.Test.{Lamp, Worlds}

  @world :sim_world

  defp dawn_region, do: Worlds.region(systems: [Lamp], time: Calendar.at(5, hour: 4))

  setup do
    on_exit(fn -> Worlds.stop_if_running(@world) end)
  end

  test "a world starts at the time its region was given, and stepping moves it" do
    {:ok, _pid} = Worlds.start(@world, region: dawn_region())

    assert {:ok, %{time: time, step: 0}} = Worlds.snapshot(@world)
    assert Calendar.format(time) == "5 AR, day 1, 04:00"

    assert {:ok, %{step: 60}} = Worlds.step(@world, 60)
    assert {:ok, %{time: later}} = Worlds.snapshot(@world)
    assert Calendar.format(later) == "5 AR, day 1, 05:00"
  end

  test "subscribers receive the events of a step with the view of the state they happened in" do
    {:ok, _owner} = Worlds.subscribe(@world)
    {:ok, _pid} = Worlds.start(@world, region: dawn_region())
    Worlds.step(@world, 120)

    lit = Calendar.at(5, hour: 6)
    assert_receive {:avwe_events, @world, [%Event{type: :lit, time: ^lit}], view}
    assert view.time == lit
  end

  test "a subscriber hears of a step with no events only if it asked to hear of every step" do
    {:ok, _pid} = Worlds.start(@world, region: dawn_region())

    parent = self()
    quiet = spawn_link(fn -> relay(parent, :quiet, false) end)
    steady = spawn_link(fn -> relay(parent, :steady, true) end)
    assert_receive {:subscribed, :quiet}
    assert_receive {:subscribed, :steady}

    Worlds.step(@world, 1)
    Worlds.step(@world, 1)

    assert_receive {:heard, :steady, [], %{step: 1}}
    assert_receive {:heard, :steady, [], %{step: 2}}
    refute_received {:heard, :quiet, _events, _view}

    # A step with events is told to both.
    Worlds.step(@world, 120)
    assert_receive {:heard, :quiet, [%Event{type: :lit}], _view}
    assert_receive {:heard, :steady, [%Event{type: :lit}], _view}

    for pid <- [quiet, steady], do: send(pid, :stop)
  end

  # A process that subscribes as asked and passes on what it hears, tagged.
  defp relay(parent, tag, steps?) do
    {:ok, _owner} = Registry.register(Avwe.PubSub, {:events, @world}, steps?)
    send(parent, {:subscribed, tag})
    relay_loop(parent, tag)
  end

  defp relay_loop(parent, tag) do
    receive do
      {:avwe_events, @world, events, view} ->
        send(parent, {:heard, tag, events, view})
        relay_loop(parent, tag)

      :stop ->
        :ok
    end
  end

  test "a world with a live clock steps by itself" do
    {:ok, _owner} = Registry.register(Avwe.PubSub, {:events, @world}, true)
    {:ok, _pid} = Worlds.start(@world, region: dawn_region(), clock: {:live, 5})

    for step <- 1..3 do
      assert_receive {:avwe_events, @world, _events, %{step: ^step}}, 10_000
    end
  end

  test "the same world cannot be started twice, and stopping it frees its name" do
    {:ok, pid} = Worlds.start(@world, region: dawn_region())
    assert {:error, {:already_started, ^pid}} = Worlds.start(@world, region: dawn_region())

    assert World.whereis(@world) == pid
    assert :ok = Worlds.stop(@world)
    assert World.whereis(@world) == nil
    assert Worlds.stop(@world) == {:error, :not_found}
    assert {:ok, _pid} = Worlds.start(@world, region: dawn_region())
  end

  test "worlds are listed with what each says of itself" do
    other = :sim_other_world

    {:ok, _pid} = Worlds.start(@world, region: dawn_region(), info: %{name: "Dawn", tagline: nil})
    {:ok, _pid} = Worlds.start(other, region: dawn_region())
    on_exit(fn -> Worlds.stop_if_running(other) end)

    assert World.info(@world) == {:ok, %{name: "Dawn", tagline: nil}}
    assert World.info(:sim_nowhere) == :error

    assert [{^other, %{name: "sim_other_world"}}, {@world, %{name: "Dawn"}}] =
             Enum.filter(World.list(), fn {id, _info} -> id in [@world, other] end)
  end

  test "a region that is not there is not found" do
    assert Worlds.snapshot(:sim_nowhere) == {:error, :not_found}
  end
end
