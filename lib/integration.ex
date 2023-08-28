defmodule Bonfire.Boundaries.Integration do
  alias Bonfire.Common.Config
  # alias Bonfire.Common.Utils
  # import Untangle

  def repo, do: Config.repo()

  def is_local?(thing) do
    if Bonfire.Common.Extend.module_enabled?(Bonfire.Federate.ActivityPub.AdapterUtils) do
      Bonfire.Federate.ActivityPub.AdapterUtils.is_local?(thing)
    end
  end
end
