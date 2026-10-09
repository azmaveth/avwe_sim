defmodule Avwe.Test.Worlds do
  @moduledoc """
  Runs a world the way the platform does, for the end-to-end tests of the kernel:
  under the application's supervisor, with a region the test made, a clock that
  is stepped by hand and, with `:store`, a folder for the log and the snapshots.
  """

  alias Avwe.{Calendar, Clock, Region, RegionServer, World}

  @region {0, 0}

  @doc "The id of the one region the helpers here make."
  @spec region_id() :: term()
  def region_id, do: @region

  @doc """
  A small region that has been prepared (`Avwe.Region.prepare/1`), as a world's
  region is when it is built: two bodies, the given `:systems`, and the given
  `:time` (default noon, year 5).
  """
  @spec region(keyword()) :: Region.t()
  def region(opts \\ []) do
    [
      id: @region,
      seed: 3,
      time: Keyword.get_lazy(opts, :time, fn -> Calendar.at(5, hour: 12) end),
      systems: Keyword.get(opts, :systems, [])
    ]
    |> Region.new()
    |> Region.put_entity("wren", position: {10, 10})
    |> Region.put_entity("heron", position: {40, 40})
    |> Region.prepare()
  end

  @doc """
  Starts the world `id`. Options: `:region` (default `region/1`), and what
  `Avwe.World.start_link/1` takes besides: `:store`, `:hooks`, `:definition`,
  `:snapshot_every`, `:snapshot_keep`.
  """
  @spec start(term(), keyword()) :: DynamicSupervisor.on_start_child()
  def start(id, opts \\ []) do
    region = Keyword.get_lazy(opts, :region, &region/0)

    child =
      Keyword.merge(
        [id: id, regions: [region], clock: :manual, info: %{name: to_string(id), tagline: nil}],
        Keyword.delete(opts, :region)
      )

    DynamicSupervisor.start_child(Avwe.Worlds, {World, child})
  end

  @doc "Stops the world `id`."
  @spec stop(term()) :: :ok | {:error, :not_found}
  def stop(id) do
    case World.whereis(id) do
      nil -> {:error, :not_found}
      pid -> DynamicSupervisor.terminate_child(Avwe.Worlds, pid)
    end
  end

  @doc "Stops the world `id` if it is running, whatever the test left."
  @spec stop_if_running(term()) :: :ok
  def stop_if_running(id) do
    _ = if World.whereis(id), do: stop(id)
    :ok
  end

  @doc "Advances the world by `ticks` steps now."
  @spec step(term(), pos_integer()) :: {:ok, %{step: non_neg_integer(), time: integer()}}
  def step(id, ticks \\ 1), do: Clock.step(id, ticks)

  @doc "The latest snapshot of the world's one region."
  @spec snapshot(term()) :: {:ok, map()} | {:error, :not_found}
  def snapshot(id), do: RegionServer.snapshot(id, @region)

  @doc "Subscribes the caller to the world's events."
  @spec subscribe(term()) :: {:ok, pid()} | {:error, term()}
  def subscribe(id), do: Registry.register(Avwe.PubSub, {:events, id}, false)
end
