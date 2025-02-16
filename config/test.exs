import Config

config :logger, level: :warning

config :new_relic_agent,
  app_name: "ElixirAgentTest",
  license_key: "license_key",
  bypass_collector: true,
  automatic_attributes: [test_attribute: "test_value"],
  ignore_paths: ["/ignore/this", ~r(ignore/these/*.)],
  log: "Logger"
