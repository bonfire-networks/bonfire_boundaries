Bonfire.Common.Repo.start_link()
# {:ok, _} = Bonfire.Common.Repo.start_link()

ExUnit.start(exclude: Bonfire.Common.RuntimeConfig.skip_test_tags())
Ecto.Adapters.SQL.Sandbox.mode(Bonfire.Common.Config.repo(), :manual)
