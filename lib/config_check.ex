defmodule Bonfire.Boundaries.ConfigCheck do
  @moduledoc """
  Boot-time / CI invariants on the boundary preset configuration.

  Boundary presets are spread across several config keys in `runtime_config.ex`
  files in `:bonfire_boundaries` and `:bonfire_classify`. The relationships
  between them (a preset's dim slugs must map to a real dim, dim slugs must have
  ACL signatures, no two dims may share an ACL, etc.) are *implicit* — there's
  no schema enforcing them. Drift between the maps has caused several silent
  bugs (e.g. `open` membership and `anyone` participation sharing an ACL
  signature, leading to mis-detection of the membership dim).

  Call `validate!/0` from a test, a CI step, or a startup hook to catch drift.
  Returns `:ok` on success, raises with a clear message on failure.

  Run `iex>` `Bonfire.Boundaries.ConfigCheck.report/0` to get a non-raising
  summary of the current state.
  """

  alias Bonfire.Common.Config

  @doc """
  Runs all invariant checks. Raises on the first violation.
  """
  def validate! do
    with :ok <- check_preset_dims_resolve(),
         :ok <- check_dim_slugs_have_acls_or_are_documented(),
         :ok <- check_no_cross_dim_acl_collision(),
         :ok <- check_interact_acls_grant_follow() do
      :ok
    end
  end

  @doc """
  Returns a map of `:ok` / `{:error, reasons}` per check, without raising.
  Useful for an iex probe or a status dashboard.
  """
  def report do
    %{
      preset_dims_resolve: check_preset_dims_resolve(),
      dim_slugs_have_acls: check_dim_slugs_have_acls_or_are_documented(),
      no_cross_dim_acl_collision: check_no_cross_dim_acl_collision(),
      interact_acls_grant_follow: check_interact_acls_grant_follow()
    }
  end

  # 1. Every dim slug declared in `:group_presets[preset][dim]` must be in
  # `:preset_dimensions[dim][:slug_order]`. Otherwise the form can't render
  # the slug and detection can't match it.
  defp check_preset_dims_resolve do
    presets = Config.__get__(:group_presets, %{}, :bonfire_classify)
    preset_dimensions = Config.__get__(:preset_dimensions, %{}, :bonfire_boundaries)

    dims = [:membership, :visibility, :participation, :default_content_visibility]

    violations =
      for {preset_slug, preset} <- presets,
          dim <- dims,
          slug = preset[dim],
          is_binary(slug),
          slug not in (get_in(preset_dimensions, [dim, :slug_order]) || []) do
        "preset #{inspect(preset_slug)} declares #{dim}: #{inspect(slug)} — " <>
          "not in :preset_dimensions[#{inspect(dim)}][:slug_order]"
      end

    case violations do
      [] -> :ok
      _ -> {:error, violations}
    end
  end

  # 2. Every slug in `:preset_dimensions[dim][:slug_order]` is either a key in
  # `:preset_acls` (even with an empty `[]` value, which forward-declares
  # federation-gated slugs) or one of the explicitly-circle-controlled slugs.
  # The allowlist below enumerates the only slugs whose membership/posting is
  # governed by circle membership rather than by ACL grants.
  @circle_controlled %{
    membership: ~w(invite_only),
    visibility: ~w(),
    participation: ~w(group_members moderators),
    default_content_visibility: ~w()
  }

  defp check_dim_slugs_have_acls_or_are_documented do
    preset_dimensions = Config.__get__(:preset_dimensions, %{}, :bonfire_boundaries)
    preset_acls = Config.__get__(:preset_acls, %{})

    violations =
      for {dim, circle_controlled} <- @circle_controlled,
          slug <- get_in(preset_dimensions, [dim, :slug_order]) || [],
          not Map.has_key?(preset_acls, slug),
          slug not in circle_controlled do
        "dim slug #{inspect(slug)} (#{dim}) has no :preset_acls entry and isn't a circle-controlled slug"
      end

    case violations do
      [] -> :ok
      _ -> {:error, violations}
    end
  end

  # 3. No two slugs in different dims of the derived dim-ACL map share an ACL
  # atom. If they did, `group_dimension_slugs/1` would be ambiguous — exactly the
  # bug that made `open` membership "win" when a group had `participation: anyone`.
  # The map is derived (no longer a config), so this check is effectively a
  # tautology against `:preset_acls` + `:preset_dimensions[dim][:slug_order]`.
  defp check_no_cross_dim_acl_collision do
    dim_acls = Bonfire.Boundaries.Presets.dim_acls()

    by_acl =
      for {dim, slugs} <- dim_acls,
          {slug, acls} <- slugs,
          acl <- acls do
        {acl, {dim, slug}}
      end
      |> Enum.group_by(fn {acl, _} -> acl end, fn {_, ds} -> ds end)

    violations =
      for {acl, ds_list} <- by_acl,
          dims = ds_list |> Enum.map(&elem(&1, 0)) |> Enum.uniq(),
          length(dims) > 1 do
        "ACL #{inspect(acl)} is claimed by multiple dims: #{inspect(ds_list)}"
      end

    case violations do
      [] -> :ok
      _ -> {:error, violations}
    end
  end

  # 4. Every `*_interact` ACL must grant `:follow` to its `:local` subject when
  # the grant is an explicit verb list. Without it, a user clicking Follow on a
  # discoverable group falls through to the boundary's request path and creates
  # a join-request-shaped row instead of a Follow — conflating Follow and Join.
  # (See the announcement-channel regression that added `verbs_interaction` to
  # the `*_interact` ACLs.)
  #
  # Skipped on purpose:
  # - `:guest` and `:activity_pub` — guests can't follow without an identity, and
  #   the activity_pub stereotype follows are governed by federation, not this ACL.
  # - role-based grants (atom values like `:interact`) — those expand to verb sets
  #   resolved by the role system; not a flat verb list to check.
  defp check_interact_acls_grant_follow do
    grants = Config.__get__(:grants, %{}, :bonfire_boundaries) |> Enum.into(%{})

    violations =
      for {acl_name, subjects_to_verbs} <- grants,
          to_string(acl_name) =~ "interact",
          {:local, verbs} <- subjects_to_verbs,
          is_list(verbs),
          :follow not in verbs do
        "ACL #{inspect(acl_name)} grants `:local` #{inspect(verbs)} — missing " <>
          "`:follow`. Add `verbs_interaction` to make the ACL actually permit " <>
          "the interaction the name advertises."
      end

    case violations do
      [] -> :ok
      _ -> {:error, violations}
    end
  end
end
