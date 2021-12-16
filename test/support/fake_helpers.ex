defmodule Bonfire.Boundaries.Test.FakeHelpers do

  alias Bonfire.Data.Identity.Account
  alias Bonfire.Me.Fake
  alias Bonfire.Me.{Accounts, Users}
  import ExUnit.Assertions

  import Bonfire.Boundaries
  require Bonfire.Common.Extend

  Bonfire.Common.Extend.import_if_enabled(Bonfire.Me.Fake)


end
