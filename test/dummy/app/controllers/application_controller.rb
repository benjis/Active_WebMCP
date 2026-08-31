# frozen_string_literal: true

class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception
  rescue_from ActionController::InvalidAuthenticityToken do
    render json: { error: "invalid_csrf" }, status: :unprocessable_entity
  end

  private

  def current_tenant
    session[:tenant_id] == "south" ? "south" : "north"
  end

  def current_favourites
    Favourite.where(tenant_id: current_tenant, user_id: session[:user_id])
  end
end
