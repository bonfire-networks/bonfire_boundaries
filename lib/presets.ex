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
    # debug(acl)

    preset_acls = Config.get!(:preset_acls_match)

    # TODO: refactor to use preset_dimensions ?

    open_acl_ids =
      (preset_acls["open"] || [])
      |> Enum.map(&Acls.get_id!/1)

    visible_acl_ids =
      (preset_acls["global"] || [])
      |> Enum.map(&Acls.get_id!/1)

    cond do
      acl_id in visible_acl_ids -> {"global", l("Global")}
      acl_id in open_acl_ids -> {"open", l("Open")}
      true -> opts[:custom_tuple] || {"custom", l("Custom")}
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
  Looks up metadata for a preset value.

  Handles the shapes `{slug, _}`, `slug` (binary), `%{slug: slug}`, and
  circle/ACL tuples that already carry their own icon data (returns `nil` for
  those so the caller falls through to its own rendering logic).

  Returns `nil` when no config entry is found.
  """
  # Circle/ACL with its own icon — don't override with config
  def for_preset({_id, %{icon: _}}), do: nil
  def for_preset({id, _name}), do: Map.get(all(), id)
  def for_preset(slug) when is_binary(slug), do: Map.get(all(), slug)
  def for_preset(%{slug: slug}), do: Map.get(all(), to_string(slug))
  def for_preset(_), do: nil
end
