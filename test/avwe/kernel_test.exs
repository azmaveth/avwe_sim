defmodule Avwe.KernelTest do
  @moduledoc """
  The simulation names nothing that lives above it: not a module of the agent
  layer or of a rule, and not a word for a body, a percept, an intent or a piece of
  physics, in code or in documentation (AVWE's `docs/engine-spec.md`, 6 and 10).
  This project depends on nothing of AVWE's, so the compiler holds the first half;
  the test holds the second, and that the files refer to nothing but themselves.
  """

  use ExUnit.Case, async: true

  alias Avwe.Test.Boundary

  # The names of the registries the application starts and the kernel uses.
  @names ["Avwe.Registry", "Avwe.PubSub", "Avwe.Worlds", "Avwe.Sim.Supervisor"]

  @agent_words ~w(body bodies percept percepts intent intents)
  @physics_words ~w(earthlike earth-like hearth hearths river rivers smoke silt kiln kilns
                    weather spring wind heat fire)

  @files Path.wildcard(Path.expand("../../lib/**/*.ex", __DIR__))

  test "the files of the project are found" do
    assert length(@files) > 15
  end

  test "the kernel refers to nothing but the kernel" do
    kernel =
      :avwe_sim
      |> Application.spec(:modules)
      |> MapSet.new(&inspect/1)
      |> MapSet.union(MapSet.new(@names))

    for file <- @files do
      outside = file |> Boundary.references() |> MapSet.difference(kernel)

      assert MapSet.to_list(outside) == [],
             "#{Path.relative_to_cwd(file)} refers to #{Enum.join(outside, ", ")}, which is not the kernel's"
    end
  end

  test "the kernel names no body, percept or intent, and no Earth-like physics" do
    for file <- @files do
      assert Boundary.words(file, @agent_words ++ @physics_words) == [],
             "#{Path.relative_to_cwd(file)} uses a word that is not the kernel's"
    end
  end
end
