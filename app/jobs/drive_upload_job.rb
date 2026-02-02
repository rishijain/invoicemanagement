require 'google/apis/drive_v3'
require 'googleauth'
require 'googleauth/stores/file_token_store'

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
    SheetUpdateJob.perform_now(invoice.id)

  rescue StandardError => e
    invoice.mark_step_failed!('drive_upload', e.message)
    raise # Re-raise to trigger retry
  end

  private

  def upload_to_google_drive(invoice)
    Rails.logger.info "☁️ Uploading image to Google Drive for invoice ##{invoice.id}"

    # Initialize Google Drive service
    service = Google::Apis::DriveV3::DriveService.new
    service.authorization = get_google_credentials

    # Prepare file metadata
    folder_id = ENV['GOOGLE_DRIVE_FOLDER_ID'] || Rails.application.credentials.google_drive_folder_id
    vendor_name = invoice.extracted_data['particulars'] || 'Unknown'
    date = invoice.extracted_data['date'] || Time.current.strftime('%Y-%m-%d')

    # Create filename: "YYYY-MM-DD - Vendor Name - Invoice ID.jpg"
    filename = "#{date} - #{vendor_name} - Invoice #{invoice.id}.jpg"

    file_metadata = {
      name: filename,
      parents: [folder_id]
    }

    # Upload the file
    invoice.image.open do |file|
      uploaded_file = service.create_file(
        file_metadata,
        fields: 'id, webViewLink, webContentLink',
        upload_source: file.path,
        content_type: invoice.image.content_type
      )

      file_id = uploaded_file.id
      # Use webViewLink for private access (requires Google account)
      drive_url = uploaded_file.web_view_link

      Rails.logger.info "✅ Uploaded to Google Drive: #{filename}"

      [drive_url, file_id]
    end
  end

  def get_google_credentials
    client_id = ENV['GOOGLE_OAUTH_CLIENT_ID'] || Rails.application.credentials.dig(:google_oauth, :client_id)
    client_secret = ENV['GOOGLE_OAUTH_CLIENT_SECRET'] || Rails.application.credentials.dig(:google_oauth, :client_secret)

    authorizer = Google::Auth::UserAuthorizer.new(
      Google::Auth::ClientId.new(client_id, client_secret),
      'https://www.googleapis.com/auth/drive.file',
      Google::Auth::Stores::FileTokenStore.new(file: Rails.root.join('tmp', 'google_tokens.yaml'))
    )

    credentials = authorizer.get_credentials('default')

    if credentials.nil?
      raise "No Google OAuth credentials found. Run: bin/rails google:authorize"
    end

    credentials
  end
end
