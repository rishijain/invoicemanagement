class RemoveManualDateFromInvoices < ActiveRecord::Migration[8.1]
  def change
    remove_column :invoices, :manual_date, :date
  end
end
