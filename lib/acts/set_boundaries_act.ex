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

        # or the opening post of the thread a post was placed in without replying to anything (see `Bonfire.Social.Acts.Threaded`), whose audience it follows the same way
        reply_to = epic.assigns[:reply_to] || epic.assigns[:context_thread]

        boundary_options =
          cond do
            context_options != [] ->
              context_options

            reply_to && Bonfire.Common.Types.object_type(reply_to) != Bonfire.Data.Social.Message ->
              case Acls.requested_boundary(options) do
                # requested when requested in ["mentions", "private"] ->
                #   Acls.retain_reply_denials(reply_to, options)

                "reply_participants" ->
                  Acls.narrow_reply_options(reply_to, [])

                # "same as the original post", as the reply composer offers it. Despite the name, this copies the post replied to (`reply_to`), not the thread (`context_id`), which is what `clone_context` means in `Acls.prepare_cast`: the `boundary: {:clone, reply_to}` merged in here is read first
                "clone_context" ->
                  Acls.inherit_reply_options(reply_to)

                # the audience the author chose, even if broader or narrower than the parent's (the UI defaults to the parent's, but doesn't stop anyone opening up); the parent's blocks still apply
                requested when is_binary(requested) ->
                  Acls.retain_reply_denials(reply_to, options)

                # none chosen (or a `{:clone_context, label}` from the composer): the parent's
                _ ->
                  Acls.inherit_reply_options(reply_to)
              end

            true ->
              []
          end

        changeset
        |> Acls.cast(current_user, Keyword.merge(options, boundary_options))
        |> Epic.assign(epic, on, ...)

      changeset.action == :delete ->
        # TODO: deletion
        epic
    end
  end
end
