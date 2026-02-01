require 'google/apis/sheets_v4'
require 'googleauth'
require 'googleauth/stores/file_token_store'

class SheetUpdateJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: 5.seconds, attempts: 3

  def perform(invoice_id)
    invoice = Invoice.find(invoice_id)

    # Skip if already completed (idempotent)
    return if invoice.sheet_update_completed?

    # Ensure previous steps are complete
    unless invoice.parsing_completed? && invoice.drive_upload_completed?
      Rails.logger.warn "⚠️ Previous steps not complete for invoice ##{invoice.id}, skipping sheet update"
      return
    end

    # Update status to processing
    invoice.update!(sheet_update_status: 'processing')

    # Append to Google Sheet
    row_number, sheet_url = append_to_google_sheet(invoice)

    # Mark sheet update complete (this is the final step!)
    invoice.mark_sheet_update_complete!(row_number, sheet_url)

    Rails.logger.info "✅ Invoice ##{invoice.id} fully processed!"

  rescue StandardError => e
    invoice.mark_step_failed!('sheet_update', e.message)
    raise # Re-raise to trigger retry
  end

  private

  def append_to_google_sheet(invoice)
    Rails.logger.info "📊 Appending to Google Sheet for invoice ##{invoice.id}"

    # Initialize Google Sheets service
    service = Google::Apis::SheetsV4::SheetsService.new
    service.authorization = get_google_credentials

    sheet_id = Rails.application.credentials.google_sheet_id

    # Prepare row data from extracted invoice data
    data = invoice.extracted_data
    row = [
      data['date'] || '',
      data['vendor_name'] || '',
      data['invoice_number'] || '',
      data['total_amount'] || '',
      data['tax_amount'] || '',
      data['currency'] || '',
      invoice.google_drive_url || '',
      Time.current.strftime('%Y-%m-%d %H:%M:%S')
    ]

    # Append to sheet (appends to first empty row)
    range = 'Sheet1!A:H'  # Adjust sheet name if needed
    value_range = Google::Apis::SheetsV4::ValueRange.new(values: [row])

    result = service.append_spreadsheet_value(
      sheet_id,
      range,
      value_range,
      value_input_option: 'USER_ENTERED'
    )

    # Extract row number from updated range (e.g., "Sheet1!A2:H2" -> 2)
    row_number = result.updates.updated_range.split('!')[1].split(':')[0].scan(/\d+/)[0].to_i

    # Generate direct URL to this row in the sheet
    sheet_url = "https://docs.google.com/spreadsheets/d/#{sheet_id}/edit#gid=0&range=A#{row_number}"

    Rails.logger.info "✅ Appended to Google Sheet row #{row_number}"
    Rails.logger.info "   Vendor: #{data['vendor_name']}"
    Rails.logger.info "   Amount: #{data['total_amount']}"
    Rails.logger.info "   Sheet URL: #{sheet_url}"

    [row_number, sheet_url]
  end

  def get_google_credentials
    client_id = Rails.application.credentials.google_oauth[:client_id]
    client_secret = Rails.application.credentials.google_oauth[:client_secret]

    authorizer = Google::Auth::UserAuthorizer.new(
      Google::Auth::ClientId.new(client_id, client_secret),
      [
        'https://www.googleapis.com/auth/drive.file',
        'https://www.googleapis.com/auth/spreadsheets'
      ],
      Google::Auth::Stores::FileTokenStore.new(file: Rails.root.join('tmp', 'google_tokens.yaml'))
    )

    credentials = authorizer.get_credentials('default')

    if credentials.nil?
      raise "No Google OAuth credentials found. Run: bin/rails google:authorize"
    end

    credentials
  end
end
