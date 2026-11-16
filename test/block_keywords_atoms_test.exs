defmodule Bonfire.Boundaries.BlockKeywordsAtomsTest do
  @moduledoc "Keywords and settings keys typed by a person are only ever strings: reading them never makes new atoms, which are never freed."
  use Bonfire.Boundaries.DataCase, async: true
  @moduletag :backend

  alias Bonfire.Boundaries.BlockKeywords

  defp unique(prefix),
    do: "#{prefix}_#{System.unique_integer([:positive])}_#{Enum.random(100_000..999_999)}"

  defp atom_exists?(string) do
    _ = String.to_existing_atom(string)
    true
  rescue
    ArgumentError -> false
  end

  test "compiling the lists does not turn keywords or unknown keys into atoms" do
    reject = unique("rejectword")
    warn = unique("warnword")
    stray_key = unique("straykey")

    value = %{
      :reject => [reject, "Enum", "2026"],
      :warn => [warn],
      stray_key => ["x"]
    }

    compiled = BlockKeywords.process_mrf_keyword(value)

    refute atom_exists?(reject)
    refute atom_exists?(warn)
    refute atom_exists?(stray_key)

    # control: the lists were really processed
    assert compiled[:reject_compiled]
    assert compiled[:warn_compiled]
  end

  test "reading the stored settings value does not make atoms either" do
    reject = unique("rejectword")

    value = %{reject: [reject], warn: []}

    assert %{} = BlockKeywords.settings_loaded([:activity_pub, :mrf_keyword], value)
    refute atom_exists?(reject)
  end
end
