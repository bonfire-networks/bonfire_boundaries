if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.Boundaries.API.VisibilityDataloader do
    @moduledoc "Dataloader.KV source: each object's Mastodon visibility (`Bonfire.Boundaries.Controlleds.visibility_on_objects/1`), batched per GraphQL request."

    def data, do: Dataloader.KV.new(&fetch/2)

    def fetch(:visibility, object_ids) do
      object_ids
      |> MapSet.to_list()
      |> Bonfire.Boundaries.Controlleds.visibility_on_objects()
    end

    def fetch(_batch, args), do: Map.new(args, &{&1, nil})
  end
end
