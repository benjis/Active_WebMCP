# frozen_string_literal: true

# A fresh Rails application's own implementation, not part of the gem.
gem "active_webmcp", ENV.fetch("ACTIVE_WEBMCP_PACKAGE_VERSION")
gem "capybara", "3.40.0", group: :test
gem "rspec", "~> 3.13", group: :test
gem "selenium-webdriver", "4.48.0", group: :test
gsub_file "Gemfile", /^gem "rails".*$/, 'gem "rails", "8.1.3.1"'
gsub_file "Gemfile", /^gem "propshaft".*$/, 'gem "propshaft", "1.3.2"'
gsub_file "Gemfile", /^gem "importmap-rails".*$/, 'gem "importmap-rails", "2.2.3"'
gsub_file "Gemfile", /^gem "turbo-rails".*$/, 'gem "turbo-rails", "2.0.23"'
gsub_file "config/database.yml", "# database: path/to/persistent/storage/production.sqlite3",
          "database: storage/production.sqlite3"
route 'root "hotels#index"'
route 'get "/search", to: "hotels#search_page", as: :search_page'
route 'get "/empty", to: "hotels#empty", as: :empty'
route 'get "/hotels/search", to: "hotels#search", as: :search_hotels'
route 'post "/favourites", to: "favourites#create", as: :favourites'
route 'post "/fixture_login", to: "sessions#create", as: :fixture_login'
create_file "db/migrate/20260831000000_create_favourites.rb", <<~RUBY
  class CreateFavourites < ActiveRecord::Migration[8.1]
    def change
      create_table :favourites do |t|
        t.string :user_id, null: false
        t.integer :hotel_id, null: false
      end
      add_index :favourites, [:user_id, :hotel_id], unique: true
    end
  end
RUBY
create_file "app/models/favourite.rb", <<~RUBY
  class Favourite < ApplicationRecord
    validates :user_id, :hotel_id, presence: true
  end
RUBY
create_file "app/controllers/hotels_controller.rb", <<~RUBY
  class HotelsController < ApplicationController
    webmcp_tool :search, name: "search_hotels", title: "Search hotels",
      description: "Search fixture hotels. Does not book or pay.", read_only_hint: true, untrusted_content_hint: true,
      route: :search_hotels, method: :get, execution: :json,
      parameters: { destination: { type: :string, required: true } }

    def index
      @favourites = Favourite.where(user_id: session[:user_id]).pluck(:hotel_id)
    end

    def search_page
    end

    def empty
    end

    def search
      @hotels = params[:destination] == "Sydney" ? [{ id: 1, name: "Package Harbour Hotel", destination: "Sydney" }] : []
      respond_to do |format|
        format.json { render json: { hotels: @hotels } }
        format.html
      end
    end
  end
RUBY
create_file "app/controllers/sessions_controller.rb", <<~RUBY
  # Synthetic local fixture only. Never deploy this authentication substitute.
  class SessionsController < ApplicationController
    def create
      reset_session
      session[:user_id] = params[:identity] == "bob" ? "bob" : "alice"
      redirect_to root_path, status: :see_other
    end
  end
RUBY
create_file "app/controllers/favourites_controller.rb", <<~'RUBY'
  class FavouritesController < ApplicationController
    protect_from_forgery with: :exception
    rescue_from ActionController::InvalidAuthenticityToken do
      render json: { error: "invalid_csrf" }, status: :unprocessable_entity
    end

    webmcp_tool :create, name: "add_favourite", title: "Add favourite",
      description: "Save a favourite. Does not book or pay.",
      route: :favourites, method: :post, execution: :json,
      parameters: { hotel_id: { type: :integer, required: true } }

    def create
      unless %w[alice bob].include?(session[:user_id])
        render json: { error: "login_required" }, status: :unauthorized
        return
      end
      unless params[:hotel_id].to_s.match?(/\A[1-9][0-9]*\z/)
        render json: { errors: { hotel_id: ["must be a positive integer"] } }, status: :unprocessable_entity
        return
      end
      unless session[:user_id] == "alice" && params[:hotel_id].to_s == "1"
        render json: { error: "hotel_not_allowed" }, status: :forbidden
        return
      end
      Favourite.create_or_find_by!(user_id: session[:user_id], hotel_id: 1)
      respond_to do |format|
        format.json { render json: { hotel_id: 1, saved: true } }
        format.html { redirect_to root_path, status: :see_other }
      end
    end
  end
RUBY
create_file "app/views/hotels/index.html.erb", <<~ERB
  <h1>Packaged ActiveWebMCP fixture</h1>
  <%= webmcp_tools "search_hotels" %>
  <%= webmcp_tools "add_favourite", controller: FavouritesController %>
  <p id="identity"><%= session[:user_id] || "anonymous" %></p>
  <p id="favourites">Favourite hotel IDs: <%= @favourites.join(", ") %></p>
  <%= button_to "Fixture Alice", fixture_login_path, data: { turbo: false } %>
  <%= button_to "Fixture Bob", fixture_login_path, params: { identity: "bob" }, data: { turbo: false } %>
  <%= button_to "Favourite hotel", favourites_path, params: { hotel_id: 1 }, data: { turbo: false } %>
  <%= link_to "Search only", search_page_path %>
  <%= link_to "No tools", empty_path %>
ERB
create_file "app/views/hotels/search_page.html.erb", <<~ERB
  <h1>Search only</h1>
  <%= webmcp_tools "search_hotels" %>
  <%= form_with url: search_hotels_path, method: :get, data: { turbo: false } do |form| %>
    <%= form.label :destination %>
    <%= form.text_field :destination, value: "Sydney" %>
    <%= form.submit "Search hotels" %>
  <% end %>
  <%= link_to "Write page", root_path %>
  <%= link_to "No tools", empty_path %>
ERB
create_file "app/views/hotels/empty.html.erb", '<h1>No tools selected</h1><%= link_to "Write page", root_path %>'
create_file "app/views/hotels/search.html.erb",
            "<h1>Search results</h1><% @hotels.each do |hotel| %><p><%= hotel[:name] %></p><% end %>"
create_file "config/initializers/package_fixture.rb", <<~RUBY
  # Local acceptance fixture settings, not production deployment advice.
  Rails.application.configure do
    config.force_ssl = false
    config.log_level = :warn
    config.assume_ssl = false
    config.hosts = ["127.0.0.1", "localhost", "www.example.com"]
    config.action_controller.allow_forgery_protection = true
    config.public_file_server.enabled = true
    config.active_webmcp.timeout_ms = 30_000
    config.content_security_policy do |policy|
      policy.default_src :self
      policy.script_src :self
      policy.style_src :self
      policy.img_src :self, :data
      policy.connect_src :self
      policy.object_src :none
      policy.base_uri :self
      policy.form_action :self
    end
    config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
    config.content_security_policy_nonce_directives = %w[script-src style-src]
  end
RUBY
