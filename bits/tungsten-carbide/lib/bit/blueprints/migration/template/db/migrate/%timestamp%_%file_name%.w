# Migration: %class_name%
use Tungsten:Carbide

+ %class_name% < Carbide:Migration
  -> up
    create_table :%name% -> (t)
      # Add columns here:
      # t.string  :name, null: false
      # t.text    :description
      # t.integer :count, default: 0
      # t.boolean :active, default: true
      # t.references :user, foreign_key: true
      t.timestamps

  -> down
    drop_table :%name%
