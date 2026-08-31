# frozen_string_literal: true

class Favourite < ActiveRecord::Base
  validates :tenant_id, :user_id, :hotel_id, presence: true
end
