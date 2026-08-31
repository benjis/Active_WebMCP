# frozen_string_literal: true

class ScopeFavouritesToTenants < ActiveRecord::Migration[8.1]
  def change
    # Preserve earlier fixture data in the original north tenant.
    add_column :favourites, :tenant_id, :string, null: false, default: "north"
    remove_index :favourites, %i[user_id hotel_id], unique: true
    add_index :favourites, %i[tenant_id user_id hotel_id], unique: true
  end
end
