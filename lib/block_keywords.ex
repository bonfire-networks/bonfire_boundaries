defmodule Bonfire.Boundaries.BlockKeywords do
  # Disabled: its only uses were the logging in the substring matcher, now commented out below.
  # import Untangle
  use Bonfire.Common.Config
  use Bonfire.Common.Settings
  use Bonfire.Common.E

  @behaviour Bonfire.Common.SettingsHookModule

  # The matcher the instance's list uses too, so both match the same way. This extension doesn't depend on `activity_pub`, so it is called through `maybe_apply` (nothing matches when it is missing).
  @matcher ActivityPub.MRF.KeywordMatcher

  @doc "Whether the keywords compiled by `block_keywords_settings/1` match any of `fields` of `content_map` (HTML, matched as visible text), with the same rules as the instance's list (`ActivityPub.MRF.KeywordMatcher`)"
  def text_fields_match?(content_map, fields, compiled) do
    Bonfire.Common.Utils.maybe_apply(
      @matcher,
      :match?,
      [compiled, Enum.map(fields, &Map.get(content_map, &1))],
      fallback_return: false
    )
  end

  @doc "Compiles a list of keywords for `text_fields_match?/3`, or `nil` when there is nothing to match"
  def compile_keywords(keywords),
    do: Bonfire.Common.Utils.maybe_apply(@matcher, :compile, [keywords], fallback_return: nil)

  @doc """
  The viewer's own keywords, compiled, or `nil`. Only the viewer's own settings count: the instance's list (stored under the same key) decides what is accepted from other instances and who may see local posts, not what each person sees.
  """
  def block_keywords_settings(opts \\ []) do
    # Bonfire.Common.Settings.get([:bonfire_boundaries, :filter_keywords], nil, opts)

    if Bonfire.Common.Utils.current_user_id(opts) do
      opts = Keyword.put(Bonfire.Common.Utils.to_options(opts), :one_scope_only, true)

      case Bonfire.Common.Settings.get([:activity_pub, :mrf_keyword, :reject_compiled], nil, opts) do
        %{} = compiled ->
          compiled

        # no compiled copy, eg. when a test sets the list in the process: compile it here
        _ ->
          Bonfire.Common.Settings.get([:activity_pub, :mrf_keyword, :reject], nil, opts)
          |> compile_keywords()
      end
    end
  end

  @doc "Whether the instance's own keywords match any of `fields` (HTML, matched as visible text). A local post that does is kept to its author, silently and for good: on publish (`Bonfire.Boundaries.Acts.SetBoundaries`), on edit and on a boundary change"
  def instance_match?(fields) do
    case instance_keywords_compiled() do
      nil ->
        false

      compiled ->
        Bonfire.Common.Utils.maybe_apply(@matcher, :match?, [compiled, fields],
          fallback_return: false
        ) == true
    end
  end

  # read the same way as `ActivityPub.MRF.KeywordPolicy` does: the copy compiled by `settings_loaded/2` when the instance's settings were saved, else the list compiled here
  defp instance_keywords_compiled do
    case Bonfire.Common.Config.get([:mrf_keyword, :reject_compiled], nil, :activity_pub) do
      %{} = compiled ->
        compiled

      _ ->
        case Bonfire.Common.Config.get([:mrf_keyword, :reject], nil, :activity_pub) do
          [_ | _] = keywords -> compile_keywords(keywords)
          _ -> nil
        end
    end
  end

  @doc "Boundary options for `Bonfire.Boundaries.Acls.cast/3` that leave an object to its author: the \"private\" preset (which has no ACLs of its own, and grants mentions nothing), nobody added, only the universal ACLs (`:object_default_boundaries`). An empty `boundary` would fall back to the default preset, public"
  def author_only_boundary_opts, do: [boundary: "private", to_circles: [], verb_grants: []]

  @doc "Makes an existing object its author's only: removes every ACL on it, then sets `author_only_boundary_opts/0`"
  def keep_to_author(creator, object) do
    with {_num, nil} <- Bonfire.Boundaries.Controlleds.remove_all_acls(object),
         {:ok, _} <- Bonfire.Boundaries.Acls.set(object, creator, author_only_boundary_opts()) do
      {:ok, object}
    end
  end

  @doc "Stores a user's (or, with `scope: :instance`, the instance's) keywords exactly as given: `Settings.put/3` would turn eg. \"2026\" into a number and \"Enum\" into a module"
  def put_block_keywords_settings(keywords, opts \\ []) do
    Settings.put_raw([:activity_pub, :mrf_keyword, :reject], keywords, opts)
  end

  @impl Bonfire.Common.SettingsHookModule
  def settings_hook_paths, do: [[:activity_pub, :mrf_keyword]]

  # Runs on every read of an `:activity_pub` setting, so the compile is cached. The key is a hash of the whole stored value, collision-proof (not `phash2`) because a collision would give one user's keywords to another. The default cache is in memory on this node, so the compiled pattern's reference is never serialised.
  @impl Bonfire.Common.SettingsHookModule
  def settings_loaded([:activity_pub, :mrf_keyword], mrf_keyword) do
    Bonfire.Common.Cache.maybe_apply_cached({__MODULE__, :process_mrf_keyword}, [mrf_keyword],
      cache_key:
        {__MODULE__, :mrf_keyword, :crypto.hash(:sha256, :erlang.term_to_binary(mrf_keyword))}
    )
  end

  @doc "Compiles the keywords to reject (`reject_compiled`), leaving the list itself as it was typed. Called through the cache by `settings_loaded/2`, once per distinct list."
  def process_mrf_keyword(mrf_keyword) do
    if reject = e(mrf_keyword, :reject, nil) do
      mrf_keyword
      |> Enum.into(%{})
      |> Map.put(:reject_compiled, compile_keywords(reject))
    else
      mrf_keyword
    end
  end
end
