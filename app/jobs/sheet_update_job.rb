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

    # TODO: Replace with actual Google Sheets API call
    # For now, use stub
    row_number = append_to_google_sheet(invoice)

    # Mark sheet update complete (this is the final step!)
    invoice.mark_sheet_update_complete!(row_number)

    Rails.logger.info "✅ Invoice ##{invoice.id} fully processed!"

  rescue StandardError => e
    invoice.mark_step_failed!('sheet_update', e.message)
    raise # Re-raise to trigger retry
  end

  private

  def append_to_google_sheet(invoice)
    # STUB: This will be replaced with actual Google Sheets API call
    # For now, return mock row number
    Rails.logger.info "📊 [STUB] Appending to Google Sheet for invoice ##{invoice.id}"

    # Simulate appending row with extracted data
    data = invoice.extracted_data
    Rails.logger.info "   Vendor: #{data['vendor_name']}"
    Rails.logger.info "   Invoice #: #{data['invoice_number']}"
    Rails.logger.info "   Amount: #{data['total_amount']}"
    Rails.logger.info "   Drive URL: #{invoice.google_drive_url}"

    # Return mock row number
    rand(10..1000)
  end
end
