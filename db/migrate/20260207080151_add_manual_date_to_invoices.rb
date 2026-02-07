class AddManualDateToInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :manual_date, :date
  end
end
