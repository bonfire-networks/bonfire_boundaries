import Config

config :bonfire_common,
  env: config_env(),
  otp_app: :bonfire_fail

import_config "bonfire_common.exs"

import_config "bonfire_boundaries.exs"
