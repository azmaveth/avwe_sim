# CLAUDE.md

`avwe_sim` is the simulation kernel of AVWE (a headless world simulator in Elixir): time,
state, systems, rules and their check, inputs, persistence and replay. Read AVWE's
`docs/engine-spec.md` before changing anything structural; it records the decisions and
the reasons. This project is a dependency of AVWE, which is where the worlds, the agent
layer and the adapters are.

## Rules

- **The kernel names nothing above it.** No module of AVWE's, and no word for a body, a
  percept, an intent or a piece of physics, in code or in documentation
  (`test/avwe/kernel_test.exs` lists the words). What the kernel needs of the layers above
  it (an input's order, a refusal at submit, what to do when a region is started again) is a
  protocol or a hook (`Avwe.Input`, `Avwe.Hooks`), never a call.
- **`Avwe.Region`, `Avwe.Tick`, `Avwe.Rng`, `Avwe.Calendar`, `Avwe.Space` and systems are
  pure.** Files, processes and the clock belong in `Avwe.Store`, `Avwe.RegionServer`,
  `Avwe.World` and `Avwe.Clock`. The one piece of state shared is `Avwe.SystemTable`, which
  says which module declares each system id; it is written from the code alone, so a run
  depends on nothing but the code.
- **Determinism.** Systems use only `Avwe.Tick.rng/2` for randomness, never plain `:rand`.
  Never depend on map iteration order; use `Region.with_components/2` or `Region.near/4`,
  which sort. Use `tick.dt`; never assume a step is one minute. Moments in time are checked
  with `Tick.crossed?/3`.
- **Replay must be exact.** `Avwe.Store.rebuild_from_start/1` has to reproduce
  `Region.state_hash/1`; anything that would make live and replay differ is a bug.
- **A system belongs to a rule and has an id.** `system_id/0` is `"<rule id>/<name>"`, the
  rule lists the system in its `systems/0` and says what it runs after, and a world's
  ruleset (`Avwe.Ruleset`) orders them, ties by id. A region and its snapshots hold ids,
  never modules, so moving or renaming a module is free and renaming an id is a change to
  every saved world. A rule lists in `owns/0` the state keys its systems write.
- Pure modules follow construct-reduce-convert: `new`, reducers that take and return the
  struct, converters at the end.
- **A test does not race a short real-time window.** Wait for what a test is about with
  `assert_receive` and a long timeout, not with a sleep. The tests here use inputs, systems
  and rules made for them (`test/support`), and no agent layer.
- **Deliberate breaks.** A piece is not tested until breaking one line of it, on purpose,
  fails a test.

## Commands

```bash
mix test
mix lint                    # format check, unused deps, compile with warnings as errors,
                            # credo --strict
mix dialyzer                # the first run builds the PLTs (about a minute)
scripts/sobelow
mix hex.audit               # needs the network
```

CI (`.github/workflows/`) runs all of them for every pull request and push to master.
`.githooks/` has the same checks for local use (`git config core.hooksPath .githooks`).

## With AVWE

AVWE depends on this project by path, so a change that spans both is two pull requests:
this one first. AVWE's CI checks out this repository beside it, the branch of the same
name as the pull request's if there is one, otherwise master. Keep AVWE green against
master here: a change to the kernel's public functions says what AVWE has to change.
