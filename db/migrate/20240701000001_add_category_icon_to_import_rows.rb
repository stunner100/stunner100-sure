class AddCategoryIconToImportRows < ActiveRecord::Migration[7.1]
  def change
    return unless table_exists?(:import_rows)

    add_column :import_rows, :category_icon, :string
  end
end
