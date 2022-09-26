defmodule Bonfire.Boundaries.Web.Routes do
  defmacro __using__(_) do
    quote do
      # pages anyone can view
      scope "/", Bonfire.Boundaries.Web do
        pipe_through(:browser)
      end

      # pages only guests can view
      scope "/", Bonfire.Boundaries.Web do
        pipe_through(:browser)
        pipe_through(:guest_only)
      end

      scope "/", Bonfire do
        pipe_through(:browser)
        pipe_through(:account_required)
      end

      # pages you need an account to view
      scope "/", Bonfire.Boundaries.Web do
        pipe_through(:browser)
        pipe_through(:account_required)
      end

      # pages you need to view as a user
      scope "/", Bonfire.Boundaries.Web do
        pipe_through(:browser)
        pipe_through(:user_required)

        live("/boundaries", BoundariesLive)
        live("/boundaries/:tab", BoundariesLive)
        live("/boundaries/:tab/:id", BoundariesLive)
        live("/boundaries/:tab/:id/:section", BoundariesLive, as: :boundaries)
      end

      # pages only admins can view
      scope "/", Bonfire.Boundaries.Web do
        pipe_through(:browser)
        pipe_through(:admin_required)

        # live "/boundaries/instance/", Boundaries, as: :admin_settings
      end
    end
  end
end
