# frozen_string_literal: true

# Rails application template used only by the reproducible installation check.
gem "active_webmcp", path: File.expand_path("../..", __dir__)
gsub_file "Gemfile", /^gem "rails".*$/, 'gem "rails", "8.1.3.1"'
gsub_file "Gemfile", /^gem "propshaft".*$/, 'gem "propshaft", "1.3.2"'
gsub_file "Gemfile", /^gem "importmap-rails".*$/, 'gem "importmap-rails", "2.2.3"'
gsub_file "Gemfile", /^gem "turbo-rails".*$/, 'gem "turbo-rails", "2.0.23"'
route 'root "hotels#index"'
route 'get "/hotels/search", to: "hotels#search", as: :search_hotels'
route 'post "/favourites", to: "favourites#create", as: :favourites'
route 'post "/fixture_login", to: "sessions#create", as: :fixture_login'
create_file "config/initializers/active_webmcp.rb", "Rails.application.config.active_webmcp.timeout_ms = 1_250\n"
create_file "app/controllers/hotels_controller.rb", <<~RUBY
  class HotelsController < ApplicationController
    webmcp_tool :search, name: "search_hotels", description: "Search synthetic hotels. Does not book or pay.",
      route: :search_hotels, method: :get, execution: :json,
      parameters: { destination: { type: :string, required: true } }

    def index
    end

    def search
      hotels = params[:destination] == "Sydney" ? [{ id: 1, name: "Clean app Harbour Hotel", destination: "Sydney" }] : []
      render json: { hotels: hotels }
    end
  end
RUBY
create_file "app/views/hotels/index.html.erb", <<~ERB
  <h1>Clean app generated search</h1>
  <%= webmcp_tools "search_hotels" %>
  <%= webmcp_tools "add_favourite", controller: FavouritesController %>
  <p id="favourites"><%= Array(session[:favourites]).join(", ") %></p>
ERB
create_file "app/controllers/sessions_controller.rb", <<~RUBY
  # Synthetic clean-install fixture identity, never a production login.
  class SessionsController < ApplicationController
    def create
      reset_session
      session[:fixture_identity] = "alice"
      redirect_to root_path, status: :see_other
    end
  end
RUBY
create_file "app/controllers/favourites_controller.rb", <<~RUBY
  class FavouritesController < ApplicationController
    protect_from_forgery with: :exception
    rescue_from ActionController::InvalidAuthenticityToken do
      render json: { error: "invalid_csrf" }, status: :unprocessable_entity
    end

    webmcp_tool :create, name: "add_favourite", description: "Save a synthetic hotel favourite.",
      route: :favourites, method: :post, execution: :json,
      parameters: { hotel_id: { type: :integer, required: true } }

    def create
      unless session[:fixture_identity] == "alice"
        render json: { error: "login_required" }, status: :unauthorized
        return
      end
      unless params[:hotel_id] == 1
        render json: { error: "hotel_not_allowed" }, status: :forbidden
        return
      end
      # This no-database install smoke uses a fixture cookie; the main demo uses
      # SQLite and a unique index. Duplicate prevention belongs to either app.
      session[:favourites] = Array(session[:favourites]) | [1]
      render json: { hotel_id: 1, saved: true }
    end
  end
RUBY
