class ChangeDefaultFamilyCurrencyToGhs < ActiveRecord::Migration[7.2]
  def change
    change_column_default :families, :currency, from: "USD", to: "GHS"
  end
end
