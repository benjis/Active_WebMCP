# frozen_string_literal: true

Rails.application.routes.draw do
  root "hotels#gem_write"
  get "/hotels/search", to: "hotels#search", as: :search_hotels
  post "/favourites", to: "favourites#create", as: :favourites
  post "/fixture_login", to: "sessions#create", as: :fixture_login
  get "/gem", to: "hotels#gem_demo", as: :gem_demo
  get "/gem/write", to: "hotels#gem_write", as: :gem_write
  get "/gem/cross", to: "catalogue#index"
  get "/gem/empty", to: "catalogue#empty"
  get "/gem/escape", to: "catalogue#escape"
end
