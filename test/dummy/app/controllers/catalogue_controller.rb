# frozen_string_literal: true

class CatalogueController < ApplicationController
  def index
    render layout: "gem_demo"
  end

  def empty
    render layout: "gem_demo"
  end

  def escape
    render layout: "gem_demo"
  end
end
