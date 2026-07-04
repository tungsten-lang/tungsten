# Create %file_name%s table
use Tungsten:Carbide

+ Create%class_name%s < Carbide:Migration
  -> up
    create_table :%file_name%s -> (t)
      # Add columns matching model attributes:
      # t.string  :name, null: false
      # t.string  :email
      # t.text    :description
      t.timestamps

  -> down
    drop_table :%file_name%s
