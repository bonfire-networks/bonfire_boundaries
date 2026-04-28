defmodule Bonfire.Boundaries.Presets do
  @moduledoc """
  Helpers for looking up boundary preset metadata (label, icon, description) from config.

  Merges general content boundary presets (`config :bonfire_boundaries, :presets`) with
  dimensional group boundary options (`config :bonfire_boundaries, :preset_dimensions`),
  producing a flat slug → metadata map usable by display components.
  """

  use Bonfire.Common.Utils
  use Bonfire.Common.Config
  use Bonfire.Common.Settings
  use Bonfire.Common.Localise
  use Bonfire.Common.E
  import Untangle
  alias Bonfire.Boundaries.Circles
  alias Bonfire.Data.AccessControl.Acl
  alias Bonfire.Data.Identity.Caretaker
  alias Bonfire.Boundaries.Summary
  alias Bonfire.Boundaries.Verbs
  alias Bonfire.Boundaries.Acls
  alias Bonfire.Boundaries.Controlleds
  alias Bonfire.Boundaries.Roles
  alias Bonfire.Boundaries.Queries
  alias Needle
  alias Bonfire.Data.AccessControl.Stereotyped
  alias Needle.Pointer

  @doc """
  Returns a flat map of all known slug → metadata, merging general presets and all
  dimension options. General presets take priority on slug conflicts.
  """
  def all do
    general = Bonfire.Common.Config.get(:presets, %{}, :bonfire_boundaries)

    dimension_flat =
      Bonfire.Common.Config.get(:preset_dimensions, %{}, :bonfire_boundaries)
      |> Enum.flat_map(fn
        {_dim, %{options: opts}} -> Map.to_list(opts || %{})
        {_dim, _} -> []
      end)
      |> Map.new()

    Map.merge(dimension_flat, general)
  end

  @doc """
  Returns the name of a preset boundary given a list of boundaries or other boundary representation.

  ## Examples

      iex> preset_name(["admins", "mentions"])
      "admins"

      iex> preset_name("public_remote", true)
      "public_remote"
  """
  def preset_name(boundaries, include_remote? \\ false)

  def preset_name(boundaries, include_remote?) when is_list(boundaries) do
    debug(boundaries, "inputted")
    preset_acls = Config.get!(:preset_acls)

    # Note: only one applies, in priority from most to least restrictive
    cond do
      "admins" in boundaries ->
        "admins"

      "mentions" in boundaries ->
        "mentions"

      "local" in boundaries ->
        "local"

      "unlisted" in boundaries ->
        "unlisted"

      "public" in boundaries ->
        "public"

      "public_remote" in boundaries ->
        # TODO: better
        if include_remote?, do: "public_remote", else: "public"

      "open" in boundaries or "request" in boundaries or "invite" in boundaries or
          "visible" in boundaries ->
        boundaries

      "private" in boundaries ->
        "private"

      Enum.any?(boundaries, &Map.has_key?(preset_acls, to_string(&1))) ->
        boundaries

      true ->
        # debug(boundaries, "No preset boundary set")
        nil
    end
    |> debug("computed")
  end

  def preset_name(other, include_remote?) do
    boundaries_normalise(other)
    |> preset_name(include_remote?)
  end

  @doc """
  Returns custom boundaries or a default set of boundaries to use

  ## Examples

      iex> boundaries_or_default(["local"])
      ["local"]

      iex> boundaries_or_default(nil, current_user: me)
      [{"public", "Public"}]
  """
  def boundaries_or_default(to_boundaries, context \\ [])

  def boundaries_or_default(to_boundaries, _)
      when is_list(to_boundaries) and to_boundaries != [] do
    to_boundaries
  end

  def boundaries_or_default(to_boundaries, _)
      when is_tuple(to_boundaries) do
    [to_boundaries]
  end

  def boundaries_or_default(_, context) do
    default_boundaries(context)
  end

  @doc """
  Returns default boundaries to use based on the provided context.

  ## Examples

      iex> default_boundaries()
      [{"public", "Public"}]

      iex> default_boundaries(current_user: me)
      [{"local", "Local"}]
  """
  def default_boundaries(context \\ []) do
    # default boundaries for new stuff
    case Settings.get([:bonfire_boundaries, :default_boundary_preset], :public, context) do
      :public ->
        [{"public", l("Public")}]

      :local ->
        [{"local", l("Local")}]

      :mentions ->
        [{"mentions", l("Mentions")}]

      :private ->
        [{"private", l("Private")}]

      other when is_binary(other) or is_atom(other) ->
        # debug(context, "zzzz")
        other = other |> to_string()
        [{other, e(context, :my_acls, other, nil) || other}]

      other ->
        other
    end
  end

  @doc """
  Normalizes boundaries represented as text or list.

  ## Examples

      iex> boundaries_normalise("local,public")
      ["local", "public"]

      iex> boundaries_normalise(["local", "public"])
      ["local", "public"]
  """
  def boundaries_normalise(text) when is_binary(text) do
    text
    |> String.split(",")
    |> Enum.map(&String.trim/1)
  end

  def boundaries_normalise(list) when is_list(list) do
    list
  end

  @doc """
  Like `boundaries_normalise/1` but filters out recognized preset slug strings so only
  direct ACL references (ULIDs / `%Acl{}` structs) remain. Preset slugs are handled
  separately via `acls_from_preset_boundary_names/1` and should not be passed to
  `maybe_add_direct_acl_ids`.
  """
  def boundaries_normalise_direct(list) when is_list(list) do
    preset_acls = Config.get!(:preset_acls)

    Enum.reject(list, fn b ->
      is_binary(b) and Map.has_key?(preset_acls, b)
    end)
  end

  def boundaries_normalise_direct(other) do
    boundaries_normalise(other) |> boundaries_normalise_direct()
  end

  @doc """
  Normalises `to_boundaries` input and splits it into `{direct_acl_ids, preset}` where:
  - `direct_acl_ids` — real ACL references (ULIDs / `%Acl{}` structs) that should be
    added directly to the controlled object
  - `preset` — the resolved preset name (or list of preset slugs) for `base_acls` lookup

  Used by `Acls.preset_stereotypes_and_acls/3`.
  """
  def boundaries_to_preset_tuple(to_boundaries) do
    normalized = boundaries_normalise(to_boundaries) |> debug("validated to_boundaries")
    preset = preset_name(normalized) |> debug("preset_name")

    direct =
      boundaries_normalise_direct(normalized) |> debug("direct_boundaries (non-preset IDs)")

    {direct, preset}
  end

  def boundaries_normalise(%Bonfire.Data.AccessControl.Acl{id: id}) do
    [id]
  end

  def boundaries_normalise(other) do
    warn(other, "Invalid boundaries set")
    []
  end

  @doc """
  Returns ACLs for a set of preset boundary names.

  ## Examples

      iex> acls_from_preset_boundary_names(["public"])
  """
  def acls_from_preset_boundary_names(presets) when is_list(presets),
    do: Enum.flat_map(presets, &acls_from_preset_boundary_names/1)

  def acls_from_preset_boundary_names(preset) do
    case preset do
      preset when is_binary(preset) ->
        acls = Config.get!(:preset_acls)[preset]

        if acls do
          acls
        else
          []
        end

      _ ->
        []
    end
  end

  @doc """
  Converts an ACL to a preset boundary name based on the object type.

  ## Examples

      iex> preset_boundary_from_acl(%Bonfire.Data.AccessControl.Acl{id: 1})
      {"public", "Public"}
      
  """
  def preset_boundary_from_acl(acl, object_type \\ nil)

  def preset_boundary_from_acl(
        %{verbs: verbs, __typename: Bonfire.Data.AccessControl.Acl, id: acl_id} = _summary,
        object_type
      ) do
    {Roles.preset_boundary_role_from_acl(%{verbs: verbs}),
     preset_boundary_tuple_from_acl(%Acl{id: acl_id}, object_type)}

    # |> debug("merged ACL + verbs")
  end

  def preset_boundary_from_acl(%{verbs: verbs} = _summary, _object_type) do
    Roles.preset_boundary_role_from_acl(%{verbs: verbs})
  end

  def preset_boundary_from_acl(acl, object_type) do
    preset_boundary_tuple_from_acl(acl, object_type)
  end

  @doc """
  Converts an ACL to a preset boundary tuple based on the object type.

  ## Examples

      iex> preset_boundary_tuple_from_acl(%Bonfire.Data.AccessControl.Acl{id: 1})
      {"public", "Public"}

      iex> preset_boundary_tuple_from_acl(%Bonfire.Data.AccessControl.Acl{id: 1}, :group)
      {"open", "Open"}
  """
  def preset_boundary_tuple_from_acl(acl, object_type \\ nil, opts \\ [])

  def preset_boundary_tuple_from_acl(acl, %{__struct__: schema} = _object, opts),
    do: preset_boundary_tuple_from_acl(acl, schema, opts)

  def preset_boundary_tuple_from_acl(%Acl{id: acl_id} = _acl, object_type, opts)
      when object_type in [Bonfire.Classify.Category, :group] do
    preset_dimensions = Config.get(:preset_dimensions, %{}, :bonfire_boundaries)
    membership_opts = get_in(preset_dimensions, [:membership, :options]) || %{}

    membership_slugs =
      get_in(preset_dimensions, [:membership, :slug_order]) || Map.keys(membership_opts)

    matched = match_membership_slug(acl_id, membership_slugs)

    if matched do
      label = get_in(membership_opts, [matched, :label]) || matched
      {matched, label}
    else
      # invite_only has no ACL grants — most restrictive fallback
      last_slug = List.last(membership_slugs) || "invite_only"
      label = get_in(membership_opts, [last_slug, :label]) || last_slug
      opts[:custom_tuple] || {last_slug, label}
    end
  end

  def preset_boundary_tuple_from_acl(%Acl{id: acl_id} = _acl, _object_type, opts) do
    preset_acls = Config.get!(:preset_acls_match)

    public_acl_ids = Acls.preset_acl_ids("public", preset_acls)
    unlisted_acl_ids = Acls.preset_acl_ids("unlisted", preset_acls)
    local_acl_ids = Acls.preset_acl_ids("local", preset_acls)

    cond do
      acl_id in public_acl_ids -> {"public", l("Public")}
      acl_id in unlisted_acl_ids -> {"unlisted", l("Unlisted")}
      acl_id in local_acl_ids -> {"local", l("Local Instance")}
      true -> opts[:custom_tuple] || {"mentions", l("Mentions")}
    end
  end

  def preset_boundary_tuple_from_acl(
        %{__typename: Bonfire.Data.AccessControl.Acl, id: acl_id} = _summary,
        object_type,
        opts
      ) do
    preset_boundary_tuple_from_acl(%Acl{id: acl_id}, object_type, opts)
  end

  def preset_boundary_tuple_from_acl(%{acl: %{id: _} = acl}, object_type, opts),
    do: preset_boundary_tuple_from_acl(acl, object_type, opts)

  def preset_boundary_tuple_from_acl(%{acl_id: acl}, object_type, opts),
    do: preset_boundary_tuple_from_acl(acl, object_type, opts)

  def preset_boundary_tuple_from_acl([acl], object_type, opts),
    do: preset_boundary_tuple_from_acl(acl, object_type, opts)

  def preset_boundary_tuple_from_acl(acls, object_type, opts) when is_list(acls) do
    # TODO: optimise
    presets =
      Enum.map(acls, fn acl ->
        preset_boundary_tuple_from_acl(acl, object_type, opts)
      end)
      |> Enum.uniq()

    cond do
      {"public", l("Public")} in presets -> {"public", l("Public")}
      {"local", l("Local Instance")} in presets -> {"local", l("Local Instance")}
      true -> opts[:custom_tuple] || {"mentions", l("Mentions")}
    end
  end

  def preset_boundary_tuple_from_acl(other, object_type, opts) do
    case Types.uid(other) do
      nil ->
        warn(other, "No boundary pattern matched")

        opts[:custom_tuple] || {"mentions", l("Mentions")}

      id ->
        preset_boundary_tuple_from_acl(%Acl{id: id}, object_type, opts)
    end
  end

  @doc """
  Derives the boundary preset tuple from an object's ACL, using the given object type for
  context-specific matching. Falls back to `default` (or `nil`) when undetected.
  """
  def boundary_preset(object_boundary, object_type \\ nil, default \\ nil) do
    case preset_boundary_tuple_from_acl(object_boundary, object_type) do
      {"private", _} -> {"private", l("Private")}
      {id, name} -> {id, name}
      other when not is_nil(default) -> warn(other, "no preset detected, falling back") && default
      _ -> nil
    end
  end

  @doc """
  Detects the membership dimension slug for a group by scanning all its ACLs.
  Uses `Controlleds.list_acls_on_object/1` so it finds global preset ACLs
  (not just per-object stereotype ACLs). Falls back to the most restrictive slug.
  """
  def membership_slug(group) do
    preset_dimensions = Config.get(:preset_dimensions, %{}, :bonfire_boundaries)
    membership_slugs = get_in(preset_dimensions, [:membership, :slug_order]) || []

    matched =
      Controlleds.list_acls_on_object(group)
      |> Enum.find_value(fn controlled ->
        acl_id = e(controlled, :acl_id, nil) || e(controlled, :acl, :id, nil)
        match_membership_slug(acl_id, membership_slugs)
      end)

    matched || List.last(membership_slugs) || "invite_only"
  end

  @doc """
  Looks up metadata for a preset value.

  Handles the shapes `{slug, _}`, `slug` (binary), `%{slug: slug}`, and
  circle/ACL tuples that already carry their own icon data (returns `nil` for
  those so the caller falls through to its own rendering logic).

  Returns `nil` when no config entry is found.
  """
  # Returns the first membership slug whose ACL IDs include acl_id, or nil.
  defp match_membership_slug(nil, _slugs), do: nil

  defp match_membership_slug(acl_id, slugs) do
    membership_acls = Map.get(dim_acls(), :membership, %{})

    Enum.find(slugs, fn slug ->
      expected = Enum.map(membership_acls[slug] || [], &Acls.get_id!/1)
      acl_id in expected
    end)
  end

  @doc """
  Per-dim ACL signatures for back-translating a group's stored boundaries into its
  (membership, visibility, participation) slugs. Derived from `:preset_acls` and
  the per-dim `:slug_order` list in `:preset_dimensions` — there's no separate
  `:group_dim_acls` config to keep in sync.

  Slugs with empty ACL signatures (e.g. `archipelago`, `archipelago:contributors`)
  are filtered out — they're forward-declared but federation-gated, and including
  them would make every dim ambiguous (an empty subset matches anything). Slugs
  whose ACL signatures are circle-controlled (e.g. `members:private`,
  `group_members`, `moderators`, `invite_only`) are also absent from `:preset_acls`
  and so naturally don't appear here; they're detected by absence/fallback in the
  caller.
  """
  def dim_acls do
    preset_dimensions = Config.get(:preset_dimensions, %{}, :bonfire_boundaries)
    preset_acls = Config.get!(:preset_acls)

    for dim <- [:membership, :visibility, :participation], into: %{} do
      slugs = get_in(preset_dimensions, [dim, :slug_order]) || []

      dim_map =
        for slug <- slugs,
            acls = Map.get(preset_acls, slug, []),
            acls != [],
            into: %{},
            do: {slug, acls}

      {dim, dim_map}
    end
  end

  # Circle/ACL with its own icon — don't override with config
  def for_preset({_id, %{icon: _}}), do: nil
  def for_preset({id, _name}), do: Map.get(all(), id)
  def for_preset(slug) when is_binary(slug), do: Map.get(all(), slug)
  def for_preset(%{slug: slug}), do: Map.get(all(), to_string(slug))
  def for_preset(_), do: nil

  @doc """
  Walks a group's ACLs once and derives its membership / visibility / participation slugs
  by matching each ACL id against the slug orderings in `preset_dimensions` config.

  Returns `%{membership: slug | nil, visibility: slug | nil, participation: slug | nil}`.
  Membership falls back to the most-restrictive slug (`invite_only` by default) when no ACL
  matches, mirroring `membership_slug/1`; visibility and participation return `nil` so callers
  can hide the row.
  """
  def group_dimension_slugs(group) do
    # `dim_acls/0` is derived once from `:preset_acls` + `:preset_dimensions`.
    # See its docstring for the dim-keyed contract that lets back-translation
    # disambiguate slugs whose ACL sets are subsets of one another.
    dim_acls = dim_acls()

    expected = fn dim ->
      Map.new(Map.get(dim_acls, dim, %{}), fn {slug, acls} ->
        {slug, MapSet.new(acls, &Acls.get_id!/1)}
      end)
    end

    group_acl_ids =
      Controlleds.list_acls_on_object(group)
      |> Enum.map(&(e(&1, :acl_id, nil) || e(&1, :acl, :id, nil)))
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    # Whole-set match: pick the slug whose required ACL set is fully present in
    # the group, preferring the most specific match (largest required set). This
    # disambiguates slugs whose ACLs are subsets of one another — e.g.
    # `local:contributors` requires `[locals_may_contribute]` while `anyone`
    # requires `[locals_may_contribute, remotes_may_contribute]`. The
    # per-ACL-iteration approach can't tell these apart and silently picks the
    # first one encountered.
    match_dim = fn expected_map ->
      expected_map
      |> Enum.filter(fn {_slug, ids} -> MapSet.subset?(ids, group_acl_ids) end)
      |> Enum.max_by(fn {_slug, ids} -> MapSet.size(ids) end, fn -> nil end)
      |> case do
        {slug, _} -> slug
        nil -> nil
      end
    end

    membership = match_dim.(expected.(:membership))
    visibility = match_dim.(expected.(:visibility))
    participation = match_dim.(expected.(:participation))

    membership_slugs =
      get_in(Config.get(:preset_dimensions, %{}, :bonfire_boundaries), [:membership, :slug_order]) ||
        []

    %{
      membership: membership || List.last(membership_slugs) || "invite_only",
      visibility: visibility,
      participation: participation
    }
  end

  @doc """
  Infers the group preset slug (e.g. `"private_club"`) from a dimension-slug map by matching
  against `:bonfire_classify, :group_presets` config. Returns `nil` when no preset matches, so
  callers can distinguish "known preset" from "custom / unresolvable".
  """
  def preset_slug_from_dims(%{} = dims) do
    m = dims[:membership]
    v = dims[:visibility]
    p = dims[:participation]

    Config.get(:group_presets, %{}, :bonfire_classify)
    |> Enum.find_value(fn {slug, meta} ->
      if e(meta, :membership, nil) == m and e(meta, :visibility, nil) == v and
           e(meta, :participation, nil) == p,
         do: slug
    end)
  end

  @doc """
  Audience-preset metadata (label + icon + description) for a group preset slug, from
  `:bonfire_classify, :group_presets` config. Returns `nil` when slug is `nil` or has no entry.
  """
  def group_preset_meta(nil), do: nil

  def group_preset_meta(slug) do
    case Config.get([:group_presets, slug], nil, :bonfire_classify) do
      %{} = meta when map_size(meta) > 0 -> meta
      _ -> nil
    end
  end

  @doc """
  Iconify name for a group's preset, falling back to `default` for custom (no-preset) groups.
  Reads from the `[:preset_slug]` group-scoped setting recorded at create time.
  """
  def group_icon(group, default \\ "ph:users-three-duotone") do
    with slug when is_binary(slug) and slug != "" <-
           Settings.__get__([:preset_slug], nil, scope: group),
         %{icon: icon} when is_binary(icon) <- group_preset_meta(slug) do
      icon
    else
      _ -> default
    end
  end

  @doc """
  Dimension option metadata (label + icon + description) for a given dimension and slug, from
  `:bonfire_boundaries, :preset_dimensions` config.
  """
  def dimension_meta(_dim, nil), do: nil

  def dimension_meta(dim, slug) do
    Config.get([:preset_dimensions, dim, :options, slug], nil, :bonfire_boundaries)
  end

  @doc """
  Resolves a single glanceable chip for a group in list contexts (directory rows, feed cards).

  Prefers the matching audience preset (e.g. `"Private club"`); falls back to the membership
  dimension label (e.g. `"On request"`, `"Invite only"`) for custom combinations.
  """
  def group_row_chip(group) do
    dims = group_dimension_slugs(group)

    group_preset_meta(preset_slug_from_dims(dims)) ||
      dimension_meta(:membership, dims[:membership])
  end
end
