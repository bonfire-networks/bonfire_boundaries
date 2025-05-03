defmodule Bonfire.Boundaries.Integration do
  use Bonfire.Common.Config
  alias Bonfire.Common.Utils
  # import Untangle

  def repo, do: Config.repo()

  def is_local?(thing, opts \\ []) do
    Utils.maybe_apply(Bonfire.Federate.ActivityPub.AdapterUtils, :is_local?, [thing, opts], opts)
  end

  def many(query, paginate?, opts \\ [])

  def many(query, false, opts) do
    case opts[:return] do
      :query ->
        query

      _ ->
        repo().many(query, opts)
    end
  end

  def many(query, _, opts) do
    case opts[:return] do
      :query ->
        query

      # :csv ->
      # query
      _ ->
        repo().many_paginated(query, opts)
    end
  end
end
