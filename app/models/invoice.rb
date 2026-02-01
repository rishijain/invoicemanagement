class Invoice < ApplicationRecord
  has_one_attached :image

  validates :image, presence: true

  # Overall status enum
  enum :status, {
    pending: 'pending',
    processing: 'processing',
    completed: 'completed',
    failed: 'failed'
  }, default: :pending, prefix: true

  # Individual step status enums
  enum :parsing_status, {
    pending: 'pending',
    processing: 'processing',
    completed: 'completed',
    failed: 'failed'
  }, default: :pending, prefix: :parsing

  enum :drive_upload_status, {
    pending: 'pending',
    processing: 'processing',
    completed: 'completed',
    failed: 'failed'
  }, default: :pending, prefix: :drive_upload

  enum :sheet_update_status, {
    pending: 'pending',
    processing: 'processing',
    completed: 'completed',
    failed: 'failed'
  }, default: :pending, prefix: :sheet_update

  # Scopes
  scope :ready_for_parsing, -> { where(parsing_status: 'pending') }
  scope :ready_for_drive_upload, -> { where(parsing_status: 'completed', drive_upload_status: 'pending') }
  scope :ready_for_sheet_update, -> { where(drive_upload_status: 'completed', sheet_update_status: 'pending') }
  scope :fully_completed, -> { where(sheet_update_status: 'completed', status: 'completed') }

  # Helper methods
  def mark_parsing_complete!(data)
    update!(
      extracted_data: data,
      parsing_status: 'completed'
    )
  end

  def mark_drive_upload_complete!(url, file_id)
    update!(
      google_drive_url: url,
      google_drive_file_id: file_id,
      drive_upload_status: 'completed'
    )
  end

  def mark_sheet_update_complete!(row_number, sheet_url)
    update!(
      google_sheet_row_number: row_number,
      google_sheet_url: sheet_url,
      sheet_update_status: 'completed',
      status: 'completed',
      processed_at: Time.current
    )
  end

  def mark_step_failed!(step, error)
    status_field = "#{step}_status"
    update!(
      status_field => 'failed',
      status: 'failed',
      error_message: error
    )
  end

  def all_steps_completed?
    parsing_completed? && drive_upload_completed? && sheet_update_completed?
  end
end
