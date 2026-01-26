defmodule Bonfire.Boundaries.BlockKeywords do
  import Untangle
  use Bonfire.Common.Settings

  def text_fields_match?(content_map, fields, patterns) do
    Enum.any?(fields, fn field ->
      case Map.get(content_map, field) do
        nil ->
          false

        "" ->
          false

        text when is_binary(text) ->
          text_pattern_match?(text, patterns)
          |> flood("text_pattern_match? #{text} in #{field}")

        _ ->
          false
      end
    end)
  end

  def block_keywords_settings(opts) do
    Bonfire.Common.Settings.get([:bonfire_boundaries, :filter_keywords], nil, opts)
  end

  defp text_pattern_match?(content, patterns) when is_tuple(patterns) do
    # TODO: also check confusables like in ActivityPub.MRF.KeywordPolicy ?
    :binary.match(String.downcase(content), patterns) != :nomatch
  end

  defp text_pattern_match?(content, patterns) when is_list(patterns) or is_binary(patterns) do
    String.contains?(String.downcase(content), patterns)
  end

  defp text_pattern_match?(_, _) do
    false
  end

  def settings_set_hook_process(filter_keywords) do
    List.wrap(filter_keywords)
    |> Enum.map(fn
      nil -> nil
      x when is_atom(x) -> String.downcase(to_string(x))
      x when is_binary(x) -> String.downcase(x)
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> flood("set_with_hooks filter_keywords")
  end

  def settings_load_hook_process(value) do
    :binary.compile_pattern(value)
  end
end
