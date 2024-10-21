defmodule Bonfire.Boundaries.Scaffold do
  @moduledoc """
  Provides functions to create default boundary fixtures for the instance or for users.
  """

  alias Bonfire.Boundaries.Scaffold

  defdelegate insert, to: Scaffold.Instance

  defdelegate create_default_boundaries(user, opts \\ []), to: Bonfire.Boundaries.Users
  defdelegate create_missing_boundaries(user), to: Bonfire.Boundaries.Users
end
