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
