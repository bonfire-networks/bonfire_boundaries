defmodule Bonfire.Boundaries.BlockKeywords do
  import Untangle
  use Bonfire.Common.Settings
  use Bonfire.Common.E

  @behaviour Bonfire.Common.SettingsHookModule

  def text_fields_match?(content_map, fields, patterns) do
    Enum.any?(fields, fn field ->
      case Map.get(content_map, field) do
        nil ->
          false

        "" ->
          false

        text when is_binary(text) ->
          text_pattern_match?(text, patterns)
          |> info("text_pattern_match? #{text} in #{field}")

        other ->
          info(other, "no text_pattern_match in #{field}")
          false
      end
    end)
  end

  def block_keywords_settings(opts \\ []) do
    # Bonfire.Common.Settings.get([:bonfire_boundaries, :filter_keywords], nil, opts)

    Bonfire.Common.Settings.get([:activity_pub, :mrf_keyword, :reject_compiled], nil, opts) ||
      Bonfire.Common.Settings.get([:activity_pub, :mrf_keyword, :reject], nil, opts)
  end

  def put_block_keywords_settings(keywords, opts \\ []) do
    Settings.put([:activity_pub, :mrf_keyword, :reject], keywords, opts)
  end

  defp text_pattern_match?(content, patterns) when is_tuple(patterns) and is_binary(content) do
    # TODO: also check confusables like in ActivityPub.MRF.KeywordPolicy ?
    (:binary.match(String.downcase(content), patterns) != :nomatch)
    |> info("pattern match?")
  end

  defp text_pattern_match?(content, patterns)
       when (is_list(patterns) or is_binary(patterns)) and is_binary(content) do
    String.contains?(String.downcase(content), patterns)
    |> info("contains?")
  end

  defp text_pattern_match?(_, _) do
    info("no valid pattern or content to check")
    false
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

  @doc "Downcases the keywords to reject and compiles them into one pattern (`reject_compiled`). Called through the cache by `settings_loaded/2`, once per distinct list."
  def process_mrf_keyword(mrf_keyword) do
    if reject = e(mrf_keyword, :reject, nil) do
      reject =
        reject
        |> List.wrap()
        |> Enum.flat_map(fn
          x when is_binary(x) -> [String.downcase(x)]
          x when is_atom(x) -> [String.downcase(to_string(x))]
          _ -> []
        end)

      reject_compiled =
        case reject do
          nil -> nil
          [] -> nil
          strings -> :binary.compile_pattern(strings)
        end

      mrf_keyword
      |> Enum.into(%{})
      |> Map.merge(%{reject: reject, reject_compiled: reject_compiled})
    else
      mrf_keyword
    end
  end
end
