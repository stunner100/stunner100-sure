class CategoryImport < Import
  def import!
    transaction do
      # Two-pass approach:
      # 1. First create all root categories (no parent)
      # 2. Then create subcategories and link to parents

      root_rows = rows.select { |row| row.category.blank? || row.category == "null" }
      subcategory_rows = rows.reject { |row| row.category.blank? || row.category == "null" }

      # First pass: Create root categories
      root_rows.each do |row|
        create_category_from_row(row, parent: nil)
      end

      # Second pass: Create subcategories with parent lookup
      subcategory_rows.each do |row|
        parent = family.categories.find_by(name: row.category)
        if parent.nil?
          Rails.logger.warn "Parent category '#{row.category}' not found for category '#{row.name}', creating as root category"
        end
        create_category_from_row(row, parent: parent)
      end
    end
  end

  def required_column_keys
    %i[name]
  end

  def column_keys
    %i[name notes category entity_type]
  end

  def csv_template
    template = <<-CSV
      name*,color,parent_category,classification
      Income,#22c55e,,income
      Food & Drink,#f97316,,expense
      Groceries,#407706,Food & Drink,expense
    CSV

    CSV.parse(template, headers: true)
  end

  def dry_run
    {
      categories: rows.count
    }
  end

  def max_row_count
    100
  end

  private

  def create_category_from_row(row, parent:)
    # Map CSV columns:
    # - name: category name
    # - notes: color (hex code)
    # - category: parent category name
    # - entity_type: classification (income/expense)

    # Use color from CSV or default color
    color = row.notes.presence || Category::COLORS.sample

    # Use classification from CSV or default to expense
    classification = row.entity_type.presence || "expense"

    # Normalize classification to lowercase
    classification = classification.downcase if classification.present?

    # Validate classification
    unless [ "income", "expense" ].include?(classification)
      classification = "expense"
    end

    category = family.categories.find_or_initialize_by(name: row.name)

    # Only update attributes if it's a new record
    if category.new_record?
      category.assign_attributes(
        color: color,
        classification: classification,
        lucide_icon: "shapes",
        parent: parent
      )
      category.save!
    end

    category
  end
end
