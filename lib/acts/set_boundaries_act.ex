defmodule Bonfire.Boundaries.Acts.SetBoundaries do
  alias Bonfire.Epics
  # alias Bonfire.Epics.Act
  alias Bonfire.Epics.Epic

  alias Bonfire.Boundaries.Acls
  alias Ecto.Changeset
  import Epics
  use Arrows
  require Untangle

  def run(epic, act) do
    on = Keyword.get(act.options, :on, :post)
    changeset = epic.assigns[on]
    current_user = Bonfire.Common.Utils.current_user_or_id(epic.assigns[:options])

    cond do
      epic.errors != [] ->
        maybe_debug(
          epic,
          act,
          length(epic.errors),
          "Skipping due to epic errors"
        )

        epic

      is_nil(on) or not is_atom(on) ->
        maybe_debug(epic, act, on, "Skipping due to `on` option")
        epic

      not (is_struct(current_user) or is_binary(current_user)) ->
        maybe_debug(
          epic,
          act,
          current_user,
          "Skipping due to missing current_user"
        )

        epic

      not is_struct(changeset) || changeset.__struct__ != Changeset ->
        maybe_debug(epic, act, changeset, "Skipping :#{on} due to changeset")
        epic

      changeset.action not in [:insert, :delete] ->
        maybe_debug(
          epic,
          act,
          changeset.action,
          "Skipping, no matching action on changeset"
        )

        epic

      changeset.action == :insert ->
        # boundary = epic.assigns[:options][:boundary]
        maybe_debug(epic, act, "boundaries", "Casting")

        options = List.wrap(epic.assigns[:options])
        context_options = List.wrap(epic.assigns[:published_in_boundary_options])
        reply_to = epic.assigns[:reply_to]

        boundary_options =
          cond do
            context_options != [] ->
              context_options

            reply_to && Bonfire.Common.Types.object_type(reply_to) != Bonfire.Data.Social.Message ->
              case Acls.requested_boundary(options) do
                # addressed-only presets grant no general audience, so they can never be broader than the parent (eg. Mastodon API "direct" replies arrive as `mentions`)
                requested when requested in ["mentions", "private"] ->
                  Acls.retain_reply_denials(reply_to, options)

                "reply_participants" ->
                  Acls.narrow_reply_options(reply_to, [])

                _ ->
                  Acls.inherit_reply_options(reply_to)
              end

            true ->
              []
          end
        # TEMP probe for CI
        Untangle.warn(
          epic.assigns[:published_in_acl_ids],
          "DEBUG SetBoundaries published_in_acl_ids"
        )

        changeset
        |> Acls.cast(current_user, Keyword.merge(options, boundary_options))
        |> Epic.assign(epic, on, ...)

      changeset.action == :delete ->
        # TODO: deletion
        epic
    end
  end
end
