# avwe_sim

The simulation kernel of [AVWE](https://github.com/azmaveth/AVWE), a headless world
simulator in Elixir. It is how a world evolves, and nothing of what lives in one:

- **time and ticks** (`Avwe.Tick`, `Avwe.Calendar`, `Avwe.Rng`): a step has a length,
  randomness comes from the tick, and a moment is checked with `Tick.crossed?/3`;
- **state** (`Avwe.Region`): entities as ids in component maps, fields, an
  environment, an opaque terrain, a space (`Avwe.Space`) and `Region.near/4`;
- **systems** (`Avwe.System`, `Avwe.SystemTable`) with stable ids and optional periods;
- **rules and the check that they make a world** (`Avwe.Rule`, `Avwe.RulePackage`,
  `Avwe.Ruleset`): what each owns, provides, needs and runs after, refused in plain words,
  all problems at once; the kernel's own rule is `sim` (`Avwe.Rules.Sim`, with scheduled
  changes, `Avwe.Systems.Miracles`);
- **inputs and hooks** (`Avwe.Input`, `Avwe.Hooks`): what a world is sent from outside, and
  what the layers above ask of a region that has been started again;
- **persistence and replay** (`Avwe.Store`, `Avwe.RegionServer`, `Avwe.World`,
  `Avwe.Clock`): a journal and snapshots, and a replay that reproduces the state exactly.

It knows no bodies, no percepts, no intents and no physics. A test holds it to that
(`test/avwe/kernel_test.exs`); this project depends on nothing of AVWE's, so the compiler
holds the rest. The agent layer (`play`), the Earth-like physics, the world definitions,
Quire and the adapters are in AVWE, which depends on this project.

The plan this is part of is AVWE's `docs/engine-spec.md`. This code was AVWE's own until
`99cba9e` (E2a); E2b moved it here with its tests, and the modules kept their `Avwe.*` names.

## Using it

AVWE reaches it by path (`{:avwe_sim, path: "../avwe_sim"}`, or the directory in
`AVWE_SIM_PATH`), so the two repositories are cloned side by side:

```
code/
  avwe/
  avwe_sim/
```

A project that uses it says which rules a world can run:

```elixir
config :avwe_sim,
  rule_packages: [MyApp.Rules.Physics],   # modules implementing Avwe.RulePackage
  default_preset: "physics"                # what a definition that names no ruleset runs
```

and implements `Avwe.Input` for what its worlds are sent. The application starts three
named processes the kernel uses: the registries `Avwe.Registry` and `Avwe.PubSub`, and the
`Avwe.Worlds` supervisor that worlds run under.

## Working on it

```bash
mix deps.get
mix test
mix lint          # format check, unused deps, compile with warnings as errors, credo --strict
mix dialyzer      # the first run builds the PLTs
scripts/sobelow
mix hex.audit
```

`git config core.hooksPath .githooks` turns on the same checks before a commit and a push.
`CLAUDE.md` has the rules of the code.
