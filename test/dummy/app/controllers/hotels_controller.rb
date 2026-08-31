# frozen_string_literal: true

class HotelsController < ApplicationController
  webmcp_tool :search,
              name: "search_hotels",
              title: "Search hotels",
              description: "Search synthetic hotels. Does not book or pay.",
              read_only_hint: true,
              untrusted_content_hint: true,
              route: :search_hotels,
              method: :get,
              execution: :json,
              parameters: { destination: { type: :string, required: true } }

  HOTELS = [
    { id: 1, name: "Fixture Harbour Hotel", destination: "Sydney" },
    { id: 2, name: "Fixture Garden Hotel", destination: "Melbourne" }
  ].map(&:freeze).freeze

  # Static escaping fixture, never selected on normal demonstration pages.
  ESCAPE_DESCRIPTION = "</script><script>window.metadataExecuted=true</script>&\u2028\u2029"
  webmcp_tool :search, name: "escaped_metadata", description: ESCAPE_DESCRIPTION,
                       route: :search_hotels, method: :get,
                       parameters: { destination: { type: :string, required: true } }

  def search
    if params[:destination].blank?
      render json: { error: "destination_required" }, status: :unprocessable_entity
      return
    end
    @hotels = HOTELS.select { |hotel| hotel[:destination].casecmp?(params[:destination].to_s) }
    respond_to do |format|
      format.json { render json: { hotels: @hotels } }
      format.html
    end
  end

  def gem_demo
    render layout: "gem_demo"
  end

  def gem_write
    @favourites = current_favourites.pluck(:hotel_id)
    render layout: "gem_demo"
  end
end
