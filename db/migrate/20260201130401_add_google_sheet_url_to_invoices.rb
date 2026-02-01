class AddGoogleSheetUrlToInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :google_sheet_url, :string
  end
end
