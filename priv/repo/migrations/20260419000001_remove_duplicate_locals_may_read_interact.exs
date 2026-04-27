defmodule Bonfire.Boundaries.Repo.Migrations.RemoveDuplicateLocalsMayReadInteract do
  @moduledoc false
  use Ecto.Migration

  # id column is uuid-typed; the ULID literal must be dumped to its 16-byte binary form first
  @duplicate_acl_id "10CA1SMAYREAD1NTERACTYYYYY"

  def up do
    {:ok, binary_id} = Needle.UID.dump(@duplicate_acl_id)

    repo().query!(
      "DELETE FROM bonfire_data_access_control_acl WHERE id = $1",
      [binary_id]
    )
  end

  def down, do: nil
end
