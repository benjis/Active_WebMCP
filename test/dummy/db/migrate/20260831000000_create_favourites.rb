# frozen_string_literal: true

class CreateFavourites < ActiveRecord::Migration[8.1]
  def change
    create_table :favourites do |t|
      t.string :user_id, null: false
      t.integer :hotel_id, null: false
    end
    add_index :favourites, %i[user_id hotel_id], unique: true
  end
end
