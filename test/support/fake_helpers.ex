defmodule Bonfire.Boundaries.Test.FakeHelpers do

  alias Bonfire.Data.Identity.Account
  alias Bonfire.Me.Fake
  alias Bonfire.Me.{Accounts, Users}
  import ExUnit.Assertions

  import Bonfire.Boundaries.Integration

  Bonfire.Common.Utils.import_if_available(Bonfire.Me.Fake)


end
