# frozen_string_literal: true

# Local fixture identity, NOT an authentication implementation for production.
class SessionsController < ApplicationController
  def create
    reset_session
    session[:user_id] = params[:identity] == "bob" ? "fixture-bob" : "fixture-alice"
    # Synthetic fixture login only. Real applications must check membership.
    session[:tenant_id] = params[:tenant] == "south" ? "south" : "north"
    redirect_to(params[:return_to] == "gem_write" ? gem_write_path : root_path, status: :see_other)
  end
end
