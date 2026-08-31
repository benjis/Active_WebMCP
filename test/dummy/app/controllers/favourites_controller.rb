# frozen_string_literal: true

class FavouritesController < ApplicationController
  webmcp_tool :create, name: "add_favourite",
                       title: "Add favourite",
                       description: "Save a synthetic hotel as a favourite. Does not book or pay.",
                       route: :favourites, method: :post, execution: :json,
                       parameters: { hotel_id: { type: :integer, required: true } }

  def create
    unless %w[fixture-alice fixture-bob].include?(session[:user_id])
      render json: { error: "login_required" }, status: :unauthorized
      return
    end
    unless params[:hotel_id].to_s.match?(/\A[1-9][0-9]*\z/)
      render json: { errors: { hotel_id: ["must be a positive integer"] } }, status: :unprocessable_entity
      return
    end
    allowed_id = current_tenant == "south" ? 2 : 1
    unless session[:user_id] == "fixture-alice" && params[:hotel_id].to_s == allowed_id.to_s
      render json: { error: "hotel_not_allowed" }, status: :forbidden
      return
    end
    # Idempotency is the application's responsibility. A unique index backs it.
    favourite = current_favourites.create_or_find_by!(hotel_id: allowed_id)
    respond_to do |format|
      format.json { render json: { hotel_id: favourite.hotel_id, saved: true } }
      format.html { redirect_to(params[:return_to] == "gem_write" ? gem_write_path : root_path, status: :see_other) }
    end
  end
end
