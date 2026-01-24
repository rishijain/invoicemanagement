class DriveUploadJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: 5.seconds, attempts: 3

  def perform(invoice_id)
    invoice = Invoice.find(invoice_id)

    # Skip if already completed (idempotent)
    return if invoice.drive_upload_completed?

    # Ensure parsing is complete before uploading
    unless invoice.parsing_completed?
      Rails.logger.warn "⚠️ Parsing not complete for invoice ##{invoice.id}, skipping upload"
      return
    end

    # Update status to processing
    invoice.update!(drive_upload_status: 'processing')

    # TODO: Replace with actual Google Drive API call
    # For now, use stub
    drive_url, file_id = upload_to_google_drive(invoice)

    # Mark upload complete and save URL/file_id
    invoice.mark_drive_upload_complete!(drive_url, file_id)

    # Enqueue next job in the chain
    SheetUpdateJob.perform_later(invoice.id)

  rescue StandardError => e
    invoice.mark_step_failed!('drive_upload', e.message)
    raise # Re-raise to trigger retry
  end

  private

  def upload_to_google_drive(invoice)
    # STUB: This will be replaced with actual Google Drive API call
    # For now, return mock data
    Rails.logger.info "☁️ [STUB] Uploading image to Google Drive for invoice ##{invoice.id}"

    file_id = "drive_file_#{SecureRandom.hex(8)}"
    drive_url = "https://drive.google.com/file/d/#{file_id}/view"

    [drive_url, file_id]
  end
end
