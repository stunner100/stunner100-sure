require "test_helper"

class CategoryImportTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper, ImportInterfaceTest

  setup do
    @subject = @import = imports(:category)
  end

  test "import creates categories from CSV" do
    import_csv = <<~CSV
      name,color,parent_category,classification
      Income,#22c55e,,income
      Food & Drink,#f97316,,expense
      Shopping,#3b82f6,,expense
    CSV

    @import.update!(
      raw_file_str: import_csv,
      name_col_label: "name",
      notes_col_label: "color",
      category_col_label: "parent_category",
      entity_type_col_label: "classification"
    )

    @import.generate_rows_from_csv

    @import.reload

    # Store initial count
    initial_category_count = @import.family.categories.count

    # Perform the import
    @import.publish

    # Check if import succeeded
    if @import.failed?
      fail "Import failed with error: #{@import.error}"
    end

    assert_equal "complete", @import.status

    # Check the differences
    assert_equal initial_category_count + 3, @import.family.categories.count, "Expected 3 new categories"

    # Verify categories were created correctly
    income_category = @import.family.categories.find_by(name: "Income")
    assert_not_nil income_category
    assert_equal "#22c55e", income_category.color
    assert_equal "income", income_category.classification
    assert_nil income_category.parent

    food_category = @import.family.categories.find_by(name: "Food & Drink")
    assert_not_nil food_category
    assert_equal "#f97316", food_category.color
    assert_equal "expense", food_category.classification
    assert_nil food_category.parent
  end

  test "import creates subcategories with parent relationships" do
    import_csv = <<~CSV
      name,color,parent_category,classification
      Food & Drink,#f97316,,expense
      Groceries,#407706,Food & Drink,expense
      Dining Out,#fb923c,Food & Drink,expense
    CSV

    @import.update!(
      raw_file_str: import_csv,
      name_col_label: "name",
      notes_col_label: "color",
      category_col_label: "parent_category",
      entity_type_col_label: "classification"
    )

    @import.generate_rows_from_csv
    @import.reload

    # Perform the import
    @import.publish

    assert_equal "complete", @import.status

    # Verify parent category
    food_category = @import.family.categories.find_by(name: "Food & Drink")
    assert_not_nil food_category
    assert_nil food_category.parent

    # Verify subcategories
    groceries = @import.family.categories.find_by(name: "Groceries")
    assert_not_nil groceries
    assert_equal food_category, groceries.parent
    assert_equal "expense", groceries.classification

    dining_out = @import.family.categories.find_by(name: "Dining Out")
    assert_not_nil dining_out
    assert_equal food_category, dining_out.parent
  end

  test "import uses default color when not provided" do
    import_csv = <<~CSV
      name,color,parent_category,classification
      Entertainment,,,expense
    CSV

    @import.update!(
      raw_file_str: import_csv,
      name_col_label: "name",
      notes_col_label: "color",
      category_col_label: "parent_category",
      entity_type_col_label: "classification"
    )

    @import.generate_rows_from_csv
    @import.reload

    @import.publish

    category = @import.family.categories.find_by(name: "Entertainment")
    assert_not_nil category
    assert_includes Category::COLORS, category.color
  end

  test "import uses default classification when not provided" do
    import_csv = <<~CSV
      name,color,parent_category,classification
      Miscellaneous,#6b7280,,
    CSV

    @import.update!(
      raw_file_str: import_csv,
      name_col_label: "name",
      notes_col_label: "color",
      category_col_label: "parent_category",
      entity_type_col_label: "classification"
    )

    @import.generate_rows_from_csv
    @import.reload

    @import.publish

    category = @import.family.categories.find_by(name: "Miscellaneous")
    assert_not_nil category
    assert_equal "expense", category.classification
  end

  test "import handles null string for parent category" do
    import_csv = <<~CSV
      name,color,parent_category,classification
      Income,#22c55e,null,income
    CSV

    @import.update!(
      raw_file_str: import_csv,
      name_col_label: "name",
      notes_col_label: "color",
      category_col_label: "parent_category",
      entity_type_col_label: "classification"
    )

    @import.generate_rows_from_csv
    @import.reload

    @import.publish

    category = @import.family.categories.find_by(name: "Income")
    assert_not_nil category
    assert_nil category.parent
  end

  test "import normalizes classification to lowercase" do
    import_csv = <<~CSV
      name,color,parent_category,classification
      Salary,#22c55e,,INCOME
    CSV

    @import.update!(
      raw_file_str: import_csv,
      name_col_label: "name",
      notes_col_label: "color",
      category_col_label: "parent_category",
      entity_type_col_label: "classification"
    )

    @import.generate_rows_from_csv
    @import.reload

    @import.publish

    category = @import.family.categories.find_by(name: "Salary")
    assert_not_nil category
    assert_equal "income", category.classification
  end

  test "import skips existing categories" do
    # Create a category first
    existing_category = @import.family.categories.create!(
      name: "Existing Category",
      color: "#000000",
      classification: "expense"
    )

    import_csv = <<~CSV
      name,color,parent_category,classification
      Existing Category,#ffffff,,expense
    CSV

    @import.update!(
      raw_file_str: import_csv,
      name_col_label: "name",
      notes_col_label: "color",
      category_col_label: "parent_category",
      entity_type_col_label: "classification"
    )

    @import.generate_rows_from_csv
    @import.reload

    initial_category_count = @import.family.categories.count

    @import.publish

    # Should not create a new category
    assert_equal initial_category_count, @import.family.categories.count

    # Original category should remain unchanged
    existing_category.reload
    assert_equal "#000000", existing_category.color
  end

  test "column_keys returns expected keys" do
    assert_equal %i[name notes category entity_type], @import.column_keys
  end

  test "required_column_keys returns expected keys" do
    assert_equal %i[name], @import.required_column_keys
  end

  test "dry_run returns expected counts" do
    @import.rows.create!(
      name: "Test Category",
      notes: "#6b7280",
      category: "",
      entity_type: "expense",
      currency: "USD"
    )

    assert_equal({ categories: 1 }, @import.dry_run)
  end

  test "max_row_count is limited to 100" do
    assert_equal 100, @import.max_row_count
  end
end
