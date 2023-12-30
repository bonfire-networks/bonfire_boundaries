defmodule Bonfire.Boundaries.Summary do
  use Ecto.Schema
  alias Needle.Pointer
  alias Needle.ULID
  alias Bonfire.Data.AccessControl.Circle
  alias Bonfire.Data.AccessControl.Controlled
  alias Bonfire.Data.AccessControl.Encircle
  alias Bonfire.Data.AccessControl.Grant
  alias Bonfire.Data.AccessControl.Verb

  @circle_table Circle.__schema__(:source)
  @controlled_table Controlled.__schema__(:source)
  @encircle_table Encircle.__schema__(:source)
  @grant_table Grant.__schema__(:source)
  @pointer_table Pointer.__schema__(:source)
  @verb_table Verb.__schema__(:source)

  @primary_key false
  @foreign_key_type ULID
  schema "bonfire_boundaries_summary" do
    belongs_to(:subject, Pointer, primary_key: true)
    belongs_to(:object, Pointer, primary_key: true)
    belongs_to(:verb, Verb, primary_key: true)
    field(:value, :boolean)
  end

  @create_summary_view """
  create or replace view bonfire_boundaries_summary as
  select
    pointer.id         as subject_id,
    controlled.id      as object_id,
    verb.id            as verb_id,
    agg_perms(g.value) as value
  from
    "#{@pointer_table}" pointer
    cross join "#{@controlled_table}" controlled
    cross join "#{@verb_table}" verb
    left join "#{@grant_table}" g
      on  controlled.acl_id = g.acl_id
      and g.verb_id = verb.id
    left join "#{@circle_table}" circle
      on g.subject_id = circle.id
    left join "#{@encircle_table}" encircle
      on  encircle.circle_id  = circle.id
      and encircle.subject_id = pointer.id
  where g.subject_id = pointer.id or encircle.id is not null
  group by (pointer.id, controlled.id, verb.id)
  """

  @drop_summary_view "drop view if exists boundaries_summary"

  def migrate_views do
    Ecto.Migration.execute(@create_summary_view, @drop_summary_view)
  end
end
