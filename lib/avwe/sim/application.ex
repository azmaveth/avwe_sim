defmodule Avwe.Sim.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    :ok = Avwe.Ruleset.register_known()

    children = [
      {Registry, keys: :unique, name: Avwe.Registry},
      {Registry, keys: :duplicate, name: Avwe.PubSub},
      {DynamicSupervisor, name: Avwe.Worlds, strategy: :one_for_one}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Avwe.Sim.Supervisor)
  end
end
