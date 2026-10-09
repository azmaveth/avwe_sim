defmodule AvweSim.MixProject do
  use Mix.Project

  def project do
    [
      app: :avwe_sim,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: dialyzer()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {Avwe.Sim.Application, []}
    ]
  end

  # The support modules of the tests (an input made for them, systems, a runner for
  # worlds) are compiled where this project is worked on, so that Dialyzer sees an
  # implementation of the `Avwe.Input` protocol beside the fallback. A project that
  # depends on this one gets it compiled for :prod, and none of them.
  defp elixirc_paths(env) when env in [:dev, :test], do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  # `mix lint` is what the pre-commit hook runs (about a second warm) and what
  # CI's lint job runs, step by step. Dialyzer, Sobelow and the audit are
  # slower or need the network, so they are separate (see CLAUDE.md).
  defp aliases do
    [
      lint: [
        "format --check-formatted",
        "deps.unlock --check-unused",
        "compile --warnings-as-errors",
        "credo --strict"
      ]
    ]
  end

  # The PLTs live in priv/plts (git-ignored) so CI can cache them.
  defp dialyzer do
    [
      plt_local_path: "priv/plts",
      plt_core_path: "priv/plts",
      flags: [:error_handling, :extra_return, :unknown]
    ]
  end

  # The simulation needs nothing but Erlang/OTP and Elixir: these are for
  # developing it.
  defp deps do
    [
      {:stream_data, "~> 1.4", only: [:dev, :test]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.16", only: [:dev, :test], runtime: false}
    ]
  end
end
