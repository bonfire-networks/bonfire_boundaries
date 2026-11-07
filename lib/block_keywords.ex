defmodule Bonfire.Boundaries.BlockKeywords do
  # Disabled: its only uses were the logging in the substring matcher, now commented out below.
  # import Untangle
  use Bonfire.Common.Config
  use Bonfire.Common.Settings
  use Bonfire.Common.Localise
  use Bonfire.Common.E

  @behaviour Bonfire.Common.SettingsHookModule

  # The matcher the instance's list uses too, so both match the same way. This extension doesn't depend on `activity_pub`, so it is called through `maybe_apply` (nothing matches when it is missing).
  @matcher ActivityPub.MRF.KeywordMatcher

  # No caller left: every check reads both lists (`block_keywords_lists/1`) and asks `verdict/2`, which reads the text once for both
  # @doc "Whether the keywords compiled by `block_keywords_settings/1` match any of `fields` of `content_map` (HTML, matched as visible text), with the same rules as the instance's list (`ActivityPub.MRF.KeywordMatcher`)"
  # def text_fields_match?(content_map, fields, compiled) do
  #   Bonfire.Common.Utils.maybe_apply(
  #     @matcher,
  #     :match?,
  #     [compiled, Enum.map(fields, &Map.get(content_map, &1))],
  #     fallback_return: false
  #   )
  # end

  @doc "Compiles a list of keywords for `verdict/2`, or `nil` when there is nothing to match"
  def compile_keywords(keywords),
    do: Bonfire.Common.Utils.maybe_apply(@matcher, :compile, [keywords], fallback_return: nil)

  # No caller left: replaced by `block_keywords_lists/1`, which also returns the list to warn about
  # @doc """
  # The viewer's own keywords, compiled, or `nil`. Only the viewer's own settings count: the instance's list (stored under the same key) decides what is accepted from other instances and who may see local posts, not what each person sees.
  # """
  # def block_keywords_settings(opts \\ []) do
  #   if Bonfire.Common.Utils.current_user_id(opts) do
  #     opts = Keyword.put(Bonfire.Common.Utils.to_options(opts), :one_scope_only, true)
  #
  #     case Bonfire.Common.Settings.get([:activity_pub, :mrf_keyword, :reject_compiled], nil, opts) do
  #       %{} = compiled ->
  #         compiled
  #
  #       # no compiled copy, eg. when a test sets the list in the process: compile it here
  #       _ ->
  #         Bonfire.Common.Settings.get([:activity_pub, :mrf_keyword, :reject], nil, opts)
  #         |> compile_keywords()
  #     end
  #   end
  # end

  @doc """
  The viewer's own two lists, compiled: `%{reject: compiled, warn: compiled}` (either `nil` when empty), or `nil` when there is nothing to match. `reject` hides a matching post completely, `warn` closes it behind a warning. Only the viewer's own settings count: the instance's lists (stored under the same key) decide what is accepted from other instances and what happens to local posts (`instance_verdict/1`), not what each person sees.
  """
  def block_keywords_lists(opts \\ []) do
    if Bonfire.Common.Utils.current_user_id(opts) do
      opts = Keyword.put(Bonfire.Common.Utils.to_options(opts), :one_scope_only, true)

      # one read for both lists: a `Settings.get` per list doubled the cost of every check
      mrf_keyword = Bonfire.Common.Settings.get([:activity_pub, :mrf_keyword], nil, opts)

      case {compiled_list(mrf_keyword, :reject), compiled_list(mrf_keyword, :warn)} do
        {nil, nil} -> nil
        {reject, warn} -> %{reject: reject, warn: warn}
      end
    end
  end

  defp compiled_list(nil, _key), do: nil

  defp compiled_list(mrf_keyword, key) do
    case e(mrf_keyword, :"#{key}_compiled", nil) do
      %{} = compiled ->
        compiled

      # no compiled copy, eg. when a test sets the list in the process: compile it here
      _ ->
        compile_keywords(e(mrf_keyword, key, nil))
    end
  end

  @doc "Reads some content's fields (HTML) once, for `verdict/2` (`ActivityPub.MRF.KeywordMatcher.prepare/2`)"
  def prepare(fields),
    do: Bonfire.Common.Utils.maybe_apply(@matcher, :prepare, [fields], fallback_return: nil)

  @doc "What the lists from `block_keywords_lists/1` say about some content, given as fields or as read by `prepare/1`: `:reject` (hide it completely), `:warn` (close it behind a warning) or `nil`. `reject` wins when both match"
  def verdict(_fields_or_prepared, nil), do: nil

  def verdict(fields_or_prepared, %{} = lists) do
    prepared =
      if is_list(fields_or_prepared), do: prepare(fields_or_prepared), else: fields_or_prepared

    cond do
      is_nil(prepared) -> nil
      matches?(lists[:reject], prepared) -> :reject
      matches?(lists[:warn], prepared) -> :warn
      true -> nil
    end
  end

  defp matches?(nil, _prepared), do: false

  defp matches?(compiled, prepared),
    do:
      Bonfire.Common.Utils.maybe_apply(@matcher, :match?, [compiled, prepared],
        fallback_return: false
      ) == true

  @doc """
  What the instance's own two lists say about a local post's `fields` (HTML, matched as visible text, read once for both): `:reject` keeps it to its author, silently and for good; `:warn` publishes it as asked, marked sensitive with a warning (`warn_summary/0` when it has no summary of its own); `nil` leaves it alone. Checked once per action: on publish (`Bonfire.Boundaries.Acts.SetBoundaries`), on edit, and (`:reject` only) on a boundary change
  """
  def instance_verdict(fields), do: verdict(fields, instance_lists())

  # Replaced by `instance_verdict/1`, which also tells a `warn` match from a `reject` one
  # def instance_match?(fields) do
  #   case instance_keywords_compiled() do
  #     nil ->
  #       false
  #
  #     compiled ->
  #       Bonfire.Common.Utils.maybe_apply(@matcher, :match?, [compiled, fields],
  #         fallback_return: false
  #       ) == true
  #   end
  # end

  # read the same way as `ActivityPub.MRF.KeywordPolicy` does: the copies compiled by `settings_loaded/2` when the instance's settings were saved, else the lists compiled here
  defp instance_lists do
    case {instance_compiled(:reject), instance_compiled(:warn)} do
      {nil, nil} -> nil
      {reject, warn} -> %{reject: reject, warn: warn}
    end
  end

  defp instance_compiled(key) do
    case Bonfire.Common.Config.get([:mrf_keyword, :"#{key}_compiled"], nil, :activity_pub) do
      %{} = compiled ->
        compiled

      _ ->
        case Bonfire.Common.Config.get([:mrf_keyword, key], nil, :activity_pub) do
          [_ | _] = keywords -> compile_keywords(keywords)
          _ -> nil
        end
    end
  end

  @doc "The warning given to a post that matches the instance's list to warn about and has no summary of its own: `[:activity_pub, :mrf_keyword, :warn_summary]` when set (also read by `ActivityPub.MRF.KeywordPolicy` for posts from other instances), else \"Hidden by filters\""
  def warn_summary,
    do:
      Bonfire.Common.Config.get([:mrf_keyword, :warn_summary], nil, :activity_pub) ||
        l("Hidden by filters")

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

  @doc "As `put_block_keywords_settings/2`, for the list of keywords to warn about"
  def put_warn_keywords_settings(keywords, opts \\ []) do
    Settings.put_raw([:activity_pub, :mrf_keyword, :warn], keywords, opts)
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

  @doc "Compiles the keywords to reject (`reject_compiled`) and to warn about (`warn_compiled`), leaving the lists themselves as they were typed. Called through the cache by `settings_loaded/2`, once per distinct value."
  def process_mrf_keyword(mrf_keyword) do
    Enum.reduce([:reject, :warn], mrf_keyword, fn key, mrf_keyword ->
      case e(mrf_keyword, key, nil) do
        nil ->
          mrf_keyword

        keywords ->
          mrf_keyword
          |> Enum.into(%{})
          |> Map.put(:"#{key}_compiled", compile_keywords(keywords))
      end
    end)
  end
end
