import Config

yes? = ~w(true yes 1)
no? = ~w(false no 0)

default_locale = "en"
# Only compile additional locales in prod or when explicitly requested
compile_all_locales? =
  (System.get_env("COMPILE_ALL_LOCALES") not in no? and config_env() == :prod) or
    System.get_env("COMPILE_ALL_LOCALES") in yes?

locales = if compile_all_locales?, do: [default_locale, "fr", "es", "it"], else: [default_locale]

config :bonfire_common,
  otp_app: :bonfire

# internationalisation
config :bonfire_common, Bonfire.Common.Localise.Cldr,
  default_locale: default_locale,
  # locales that will be made available on top of those for which gettext localisation files are available
  locales: locales,
  providers: [
    Cldr.Language,
    Cldr.DateTime,
    Cldr.Number,
    Cldr.Unit,
    Cldr.List,
    Cldr.Calendar,
    Cldr.Territory,
    Cldr.LocaleDisplay,
    Cldr.Trans
  ],
  gettext: Bonfire.Common.Localise.Gettext,
  data_dir: "./priv/cldr",
  add_fallback_locales: compile_all_locales?,
  # precompile_number_formats: ["¤¤#,##0.##"],
  # precompile_transliterations: [{:latn, :arab}, {:thai, :latn}]
  force_locale_download: Mix.env() == :prod,
  generate_docs: true

config :ex_cldr_units,
  default_backend: Bonfire.Common.Localise.Cldr

config :ex_cldr,
  default_locale: default_locale,
  default_backend: Bonfire.Common.Localise.Cldr,
  json_library: Jason

config :rustler_precompiled, force_build_all: System.get_env("RUSTLER_BUILD_ALL") in ["true", "1"]
