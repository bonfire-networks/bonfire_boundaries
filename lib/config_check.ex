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
         :ok <- check_interact_acls_grant_follow(),
         :ok <- check_acls_are_offered_or_declared(),
         :ok <- check_no_duplicate_signatures_within_dim(),
         :ok <- check_grid_slugs_have_a_role(),
         :ok <- check_shared_slugs_agree_on_role(),
         :ok <- check_membership_slugs_have_a_join_mode() do
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
      interact_acls_grant_follow: check_interact_acls_grant_follow(),
      acls_are_offered_or_declared: check_acls_are_offered_or_declared(),
      no_duplicate_signatures_within_dim: check_no_duplicate_signatures_within_dim(),
      grid_slugs_have_a_role: check_grid_slugs_have_a_role(),
      shared_slugs_agree_on_role: check_shared_slugs_agree_on_role(),
      membership_slugs_have_a_join_mode: check_membership_slugs_have_a_join_mode()
    }
  end

  # The two dimensions laid out as a scope × role grid, where `role` grades how much of see/read/interact an audience gets. Both ask that about content: visibility for the group itself, `default_content_visibility` for posts in it. Membership ("who may join") and participation ("who may post") ask different questions and have their own vocabularies, so their slugs carry no `role` and the grid checks below skip them.
  @grid_dims [:visibility, :default_content_visibility]

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

  # 5. The reverse of check 2: every `:preset_acls` key is either offered by some dimension's `slug_order`, or declared below. An entry nothing can select is invisible: it looks like a working slug to anyone reading the config, and `boundaries_normalise_direct/1` would read it as an ACL id if a caller ever passed it.
  #
  # `:preset_acls` is one flat map serving both single-dimension POST boundaries and the group dimensions, so a key no dimension offers is not automatically wrong. It does have to be named though, so that "nothing offers this" stays a decision.
  @acls_not_offered_by_any_dim %{
    # a post's own boundary, which has no group dimension to belong to
    ~w(private) => "post-only boundary"
  }

  defp check_acls_are_offered_or_declared do
    preset_dimensions = Config.__get__(:preset_dimensions, %{}, :bonfire_boundaries)
    preset_acls = Config.__get__(:preset_acls, %{})

    offered =
      for {_dim, meta} <- preset_dimensions,
          slug <- meta[:slug_order] || [],
          into: MapSet.new(),
          do: slug

    declared =
      for {slugs, _why} <- @acls_not_offered_by_any_dim,
          slug <- slugs,
          into: MapSet.new(),
          do: slug

    violations =
      for {slug, _acls} <- preset_acls,
          not MapSet.member?(offered, slug),
          not MapSet.member?(declared, slug) do
        ":preset_acls has #{inspect(slug)}, which no dimension's :slug_order offers. " <>
          "Either offer it, or add it to @acls_not_offered_by_any_dim with the reason."
      end

    case violations do
      [] -> :ok
      _ -> {:error, violations}
    end
  end

  # 6. Two slugs in ONE dimension must not share an ACL signature, or `Presets.match_dimension/2` is picking between them by `slug_order` position, which is a tie-break for genuinely ambiguous cases rather than a way to resolve duplicates.
  #
  # Empty signatures are exempt because they are not matchable at all: `dim_acls/0` drops them and `match_dimension/2` skips them, so a circle-controlled slug is detected by other means or not at all.
  defp check_no_duplicate_signatures_within_dim do
    violations =
      for {dim, slugs} <- Bonfire.Boundaries.Presets.dim_acls(),
          {signature, group} <-
            Enum.group_by(slugs, fn {_slug, acls} -> MapSet.new(acls) end, &elem(&1, 0)),
          MapSet.size(signature) > 0,
          length(group) > 1 do
        "#{dim} slugs #{inspect(group)} share the ACL signature #{inspect(MapSet.to_list(signature))} — " <>
          "detection cannot tell them apart"
      end

    case violations do
      [] -> :ok
      _ -> {:error, violations}
    end
  end

  # 7. Every slug the grid offers needs a `role:`, which is what says how MUCH access it grants. `Presets.swap_dim_for_scope/3` moves a dimension between scopes by finding the slug with the same role, and its `Enum.find(current, …)` falls back to leaving the dimension untouched, so a missing role makes the federate toggle silently do nothing for that slug.
  defp check_grid_slugs_have_a_role do
    preset_dimensions = Config.__get__(:preset_dimensions, %{}, :bonfire_boundaries)

    violations =
      for dim <- @grid_dims,
          slug <- get_in(preset_dimensions, [dim, :slug_order]) || [],
          is_nil(get_in(preset_dimensions, [dim, :options, slug, :role])) do
        "#{dim} offers #{inspect(slug)} with no `role:` — `swap_dim_for_scope/3` cannot move it " <>
          "between scopes, so the federate toggle will skip it silently"
      end

    case violations do
      [] -> :ok
      _ -> {:error, violations}
    end
  end

  # 8. A slug both grid dimensions offer must mean the same degree of access in each. They share one `:preset_acls` entry, so they already share their grants; disagreeing about the role would make `layer2_from_dims/1` read a different toggle state depending on which dimension it was asked about.
  defp check_shared_slugs_agree_on_role do
    preset_dimensions = Config.__get__(:preset_dimensions, %{}, :bonfire_boundaries)

    roles_by_slug =
      for dim <- @grid_dims,
          slug <- get_in(preset_dimensions, [dim, :slug_order]) || [] do
        {slug, {dim, get_in(preset_dimensions, [dim, :options, slug, :role])}}
      end
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    violations =
      for {slug, dim_roles} <- roles_by_slug,
          length(dim_roles) > 1,
          dim_roles |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length() > 1 do
        "#{inspect(slug)} is offered by both grid dimensions with different roles: #{inspect(dim_roles)}"
      end

    case violations do
      [] -> :ok
      _ -> {:error, violations}
    end
  end

  # 9. Every membership slug must say what joining it means. `Categories.join_mode/1` reads this, and its three values are a PUBLIC contract: the Mastodon-compatible groups API returns `join_mode` verbatim and derives `Account.locked` from it. A slug with none falls back to `"free"`, which would advertise a group as freely joinable on the strength of a missing config key.
  @join_modes ~w(free request invite)

  defp check_membership_slugs_have_a_join_mode do
    preset_dimensions = Config.__get__(:preset_dimensions, %{}, :bonfire_boundaries)

    violations =
      for slug <- get_in(preset_dimensions, [:membership, :slug_order]) || [],
          mode = get_in(preset_dimensions, [:membership, :options, slug, :join_mode]),
          mode not in @join_modes do
        "membership slug #{inspect(slug)} declares join_mode #{inspect(mode)} — " <>
          "must be one of #{inspect(@join_modes)}, since the groups API returns it verbatim"
      end

    case violations do
      [] -> :ok
      _ -> {:error, violations}
    end
  end
end
