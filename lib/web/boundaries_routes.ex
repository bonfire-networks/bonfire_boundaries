defmodule Bonfire.Boundaries.Web.Routes do
  def declare_routes, do: "boundaries"

  defmacro __using__(_) do
    quote do
      # pages anyone can view
      scope "/boundaries", Bonfire.Boundaries.Web do
        pipe_through(:browser)
      end

      if extension_enabled?(:bonfire_ui_me) do
        # pages only guests can view
        scope "/boundaries", Bonfire.Boundaries.Web do
          pipe_through(:browser)
          pipe_through(:guest_only)
        end

        # pages you need an account to view
        scope "/boundaries", Bonfire.Boundaries.Web do
          pipe_through(:browser)
          pipe_through(:account_required)
        end

        # pages you need to view as a user
        scope "/boundaries", Bonfire.Boundaries.Web do
          pipe_through(:browser)
          pipe_through(:user_required)

          live("/scope/:scope", BoundariesLive, as: :boundaries)
          live("/scope/:scope/:tab", BoundariesLive, as: :boundaries)
          live("/scope/:scope/:tab/:id", BoundariesLive, as: :boundaries)
          live("/scope/:scope/:tab/:id/:section", BoundariesLive, as: :boundaries)

          live("/", BoundariesLive, as: :boundaries)
          live("/:tab", BoundariesLive, as: :boundaries)
          live("/:tab/:id", BoundariesLive, as: :boundaries)
          live("/:tab/:id/:section", BoundariesLive, as: :boundaries)
        end

        # pages only admins can view
        scope "/boundaries", Bonfire.Boundaries.Web do
          pipe_through(:browser)
          pipe_through(:admin_required)

          # live "/instance/", Boundaries, as: :admin_settings
        end
      end
    end
  end
end
