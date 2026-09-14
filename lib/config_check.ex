defmodule Bonfire.Boundaries.ConfigCheck do
  @moduledoc """
  Boot-time / CI invariants on the boundary preset configuration.

  Boundary presets are spread across several config keys in the `runtime_config.ex` files of `:bonfire_boundaries` and `:bonfire_classify`. The relationships between them are implicit, with no schema enforcing them: a preset's dim slugs must map to a real dim, dim slugs must have ACL signatures, and an ACL shared across dims must be declared. Drift between the maps has caused several silent bugs, such as `open` membership and `anyone` participation sharing an ACL signature and so mis-detecting the membership dim.

  Currently run from `config_check_test.exs` only, which is what makes CI the enforcement point. `validate!/0` is safe to call from a startup hook too, but note that it raises, so wiring it into boot means an instance with drifted config refuses to start.

  Run `Bonfire.Boundaries.ConfigCheck.report/0` in IEx for a non-raising summary of the current state.
  """

  alias Bonfire.Common.Config

  @doc """
  Runs all invariant checks, raising on the first violation.
  """
  def validate! do
    with :ok <- check_preset_dims_resolve(),
         :ok <- check_dim_slugs_have_acls_or_are_documented(),
         :ok <- check_no_cross_dim_acl_collision(),
         :ok <- check_interact_acls_grant_follow() do
      :ok
    else
      {:error, violations} ->
        raise ArgumentError,
              "Boundary preset config is inconsistent:\n" <> Enum.join(violations, "\n")
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

  # 1. Every dim slug declared in `:group_presets[preset][dim]` must be in `:preset_dimensions[dim][:slug_order]`, or the form cannot render the slug and detection cannot match it.
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

  # 2. Every slug in `:preset_dimensions[dim][:slug_order]` is either a key in `:preset_acls` (even with an empty `[]` value, which forward-declares federation-gated slugs) or one of the circle-controlled slugs below, which are the only ones whose membership/posting is governed by circle membership rather than by ACL grants.
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

  # 3. An ACL atom may be shared across dims only if it is declared here, so that sharing stays a decision rather than an accident. Undeclared sharing is what made `open` membership "win" when a group had `participation: anyone`.
  # `:everyone_may_request` is shared on purpose: asking is granted by the membership dimension, and the `"local"` key is at once a post boundary and a visibility slug, so posts cannot carry it without visibility seeing it too. `Presets.match_dimension/2` settles the resulting equal-size tie by `slug_order`.
  @acls_shared_across_dims [:everyone_may_request]

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
          acl not in @acls_shared_across_dims,
          dims = ds_list |> Enum.map(&elem(&1, 0)) |> Enum.uniq(),
          length(dims) > 1 do
        "ACL #{inspect(acl)} is claimed by multiple dims: #{inspect(ds_list)}"
      end

    case violations do
      [] -> :ok
      _ -> {:error, violations}
    end
  end

  # 4. Every `*_interact` ACL must grant `:follow` to its `:local` subject when the grant is an explicit verb list. Without it, clicking Follow on a discoverable group falls through to the boundary's request path and creates a join-request-shaped row instead of a Follow, conflating Follow and Join. See the announcement-channel regression that added `verbs_interaction` to the `*_interact` ACLs.
  # Skipped on purpose: `:guest` and `:activity_pub` (guests cannot follow without an identity, and activity_pub stereotype follows are governed by federation rather than by this ACL), and role-based grants such as `:interact` (atoms expand to verb sets via the role system, so there is no flat list to check).
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
