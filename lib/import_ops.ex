defmodule Bonfire.Boundaries.ImportOps do
  @moduledoc """
  The import ops for what `bonfire_boundaries` owns: blocks, silences, ghosts (for a person or instance-wide) and circles, in the op role of `Bonfire.Common.ImportModule`. `Bonfire.Common.Import`'s worker hands each queued job to `perform_import/3`.
  """
  @behaviour Bonfire.Common.ImportModule

  use Bonfire.Common.Localise
  alias Bonfire.Common.Utils
  alias Bonfire.Boundaries.Blocks

  @impl Bonfire.Common.ImportModule
  def import_ops, do: ["blocks_import", "silences_import", "ghosts_import", "circles_import"]

  @impl Bonfire.Common.ImportModule
  def import_op_label("blocks_import"), do: l("Block")
  def import_op_label("silences_import"), do: l("Silence")
  def import_op_label("ghosts_import"), do: l("Ghost")
  def import_op_label("circles_import"), do: l("Circle")
  def import_op_label(_), do: nil

  @impl Bonfire.Common.ImportModule
  def import_op_phrase("blocks_import"), do: l("Blocking or instance")
  def import_op_phrase("silences_import"), do: l("Silencing user or instance")
  def import_op_phrase("ghosts_import"), do: l("Ghosting user or instance")
  def import_op_phrase("circles_import"), do: l("Adding to circle")
  def import_op_phrase(_), do: nil

  @doc """
  Imports one item, for the scope: called by `Bonfire.Common.Import`'s worker for each queued job of an op in `import_ops/0`. A circles item is `{circle_name, username}`.

  ## Examples

      iex> perform_import("blocks_import", "identifier", scope: :instance_wide, skip_boundary_check: true)

  """
  @impl Bonfire.Common.ImportModule
  def perform_import("silences_import" = op, identifier, scope),
    do: block(op, identifier, [:silence], scope)

  def perform_import("ghosts_import" = op, identifier, scope),
    do: block(op, identifier, [:ghost], scope)

  def perform_import("blocks_import" = op, identifier, scope),
    do: block(op, identifier, [:ghost, :silence], scope)

  def perform_import("circles_import" = op, {circle_name, username}, scope) do
    current_user = Utils.current_user(scope)

    with {:ok, user} <- find_character(username, []),
         {:ok, circle} <- Bonfire.Boundaries.Circles.get_or_create(circle_name, current_user),
         {:ok, _encircle} <-
           Bonfire.Boundaries.Circles.add_to_circles(user, circle, current_user: current_user) do
      :ok
    else
      error -> Bonfire.Common.Import.handle_error(op, "#{circle_name}; #{username}", error)
    end
  end

  defp block(op, identifier, block_types, scope) do
    with {:ok, %{} = blocked} <- find_character(identifier, add_all_domains_as_instances: true),
         {:ok, _} <- Blocks.block(blocked, block_types, scope) do
      :ok
    else
      error -> Bonfire.Common.Import.handle_error(op, identifier, error)
    end
  end

  # a local or remote profile or instance, by URL, AP id or username, fetched when not known yet
  defp find_character(identifier, opts),
    do:
      Utils.maybe_apply(
        Bonfire.Federate.ActivityPub.AdapterUtils,
        :get_by_url_ap_id_or_username,
        [identifier, opts]
      )
end
