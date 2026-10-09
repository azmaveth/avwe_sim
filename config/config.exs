import Config

# The kernel is configured by whatever uses it: `config :avwe_sim, rule_packages:
# [...], default_preset: "..."` names the packages of rules a world can run and
# the preset a definition that names no ruleset runs (`Avwe.Ruleset`). Alone it
# knows `sim`, its own rule.

# Tests pass their own data_dir; nothing is written otherwise.
if config_env() == :test do
  config :logger, level: :warning
end
