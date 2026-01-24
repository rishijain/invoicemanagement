class AddTrackingColumnsToInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :parsing_status, :string, default: 'pending'
    add_column :invoices, :drive_upload_status, :string, default: 'pending'
    add_column :invoices, :sheet_update_status, :string, default: 'pending'
    add_column :invoices, :extracted_data, :jsonb, default: {}
    add_column :invoices, :google_drive_url, :string
    add_column :invoices, :google_drive_file_id, :string
    add_column :invoices, :google_sheet_row_number, :integer
    add_column :invoices, :error_message, :text
    add_column :invoices, :processed_at, :datetime
  end
end
