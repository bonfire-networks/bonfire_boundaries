defmodule Bonfire.Boundaries.Web.EditCircleLive do
  use Bonfire.UI.Common.Web, :live_component

  def update(assigns, socket) do

      with {:ok, circle} <- Bonfire.Boundaries.Circles.get_for_caretaker(assigns.id, current_user(assigns)) |> repo().maybe_preload(encircles: [subject: [:profile, :character]]) do
        debug(circle)

      # TODO: paginate
      followed = Bonfire.Social.Follows.list_my_followed(current_user(assigns), paginate: false) #|> IO.inspect
      followers = Bonfire.Social.Follows.list_my_followers(current_user(assigns), paginate: false) #|> IO.inspect

      {:ok, assign(socket, assigns
      |> assigns_merge(%{circle: circle, followers: followers, followed:  followed}))}
    end
  end
end
