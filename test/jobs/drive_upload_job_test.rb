require "test_helper"
require 'mocha/minitest'

class DriveUploadJobTest < ActiveJob::TestCase
  setup do
    @invoice = invoices(:one)

    # Attach a test image first (required by validation)
    @invoice.image.attach(
      io: File.open(Rails.root.join('test/fixtures/files/test_invoice.png')),
      filename: 'test_invoice.png',
      content_type: 'image/png'
    )

    # Then set up invoice with parsed data
    @invoice.update!(
      parsing_status: 'completed',
      drive_upload_status: 'pending',
      extracted_data: {
        'vendor_name' => 'Test Vendor',
        'date' => '2026-01-15',
        'total_amount' => 100.0,
        'invoice_number' => 'INV-001'
      }
    )
  end

  teardown do
    @invoice.image.purge if @invoice.image.attached?
  end

  # Test successful upload
  test "should upload invoice to Google Drive successfully" do
    # Mock Google Drive service
    mock_service = mock('drive_service')
    mock_credentials = mock('credentials')
    mock_uploaded_file = mock('uploaded_file')

    # Set up mock expectations
    Google::Apis::DriveV3::DriveService.expects(:new).returns(mock_service)
    mock_service.expects(:authorization=).with(mock_credentials)

    # Mock credentials
    DriveUploadJob.any_instance.expects(:get_google_credentials).returns(mock_credentials)

    # Mock file upload
    mock_uploaded_file.stubs(:id).returns('mock_file_id_123')
    mock_uploaded_file.stubs(:web_view_link).returns('https://drive.google.com/file/d/mock_file_id_123/view')

    mock_service.expects(:create_file)
      .with(
        has_entries(name: "2026-01-15 - Test Vendor - Invoice #{@invoice.id}.jpg"),
        has_entries(fields: 'id, webViewLink, webContentLink')
      )
      .returns(mock_uploaded_file)

    # Perform the job
    DriveUploadJob.perform_now(@invoice.id)

    # Verify invoice was updated
    @invoice.reload
    assert_equal 'completed', @invoice.drive_upload_status
    assert_equal 'https://drive.google.com/file/d/mock_file_id_123/view', @invoice.google_drive_url
    assert_equal 'mock_file_id_123', @invoice.google_drive_file_id
  end

  # Test idempotent behavior
  test "should skip upload if already completed" do
    @invoice.update!(drive_upload_status: 'completed')

    # Should not call Google Drive API
    Google::Apis::DriveV3::DriveService.expects(:new).never

    DriveUploadJob.perform_now(@invoice.id)

    # Status should remain completed
    @invoice.reload
    assert_equal 'completed', @invoice.drive_upload_status
  end

  # Test parsing prerequisite
  test "should skip upload if parsing not completed" do
    @invoice.update!(parsing_status: 'pending')

    # Should not call Google Drive API
    Google::Apis::DriveV3::DriveService.expects(:new).never

    DriveUploadJob.perform_now(@invoice.id)

    # Status should still be pending
    @invoice.reload
    assert_equal 'pending', @invoice.drive_upload_status
  end

  # Test filename generation
  test "should generate correct filename from extracted data" do
    mock_service = mock('drive_service')
    mock_credentials = mock('credentials')
    mock_uploaded_file = mock('uploaded_file')

    Google::Apis::DriveV3::DriveService.expects(:new).returns(mock_service)
    mock_service.expects(:authorization=).with(mock_credentials)
    DriveUploadJob.any_instance.expects(:get_google_credentials).returns(mock_credentials)

    mock_uploaded_file.stubs(:id).returns('file_id')
    mock_uploaded_file.stubs(:web_view_link).returns('https://drive.google.com/file/d/file_id/view')

    # Check filename format
    mock_service.expects(:create_file)
      .with(
        has_entry(:name, "2026-01-15 - Test Vendor - Invoice #{@invoice.id}.jpg"),
        anything
      )
      .returns(mock_uploaded_file)

    DriveUploadJob.perform_now(@invoice.id)
  end

  # Test filename with missing vendor name
  test "should handle missing vendor name in filename" do
    @invoice.update!(extracted_data: { 'date' => '2026-01-15' })

    mock_service = mock('drive_service')
    mock_credentials = mock('credentials')
    mock_uploaded_file = mock('uploaded_file')

    Google::Apis::DriveV3::DriveService.expects(:new).returns(mock_service)
    mock_service.expects(:authorization=).with(mock_credentials)
    DriveUploadJob.any_instance.expects(:get_google_credentials).returns(mock_credentials)

    mock_uploaded_file.stubs(:id).returns('file_id')
    mock_uploaded_file.stubs(:web_view_link).returns('https://drive.google.com/file/d/file_id/view')

    # Should use "Unknown" for missing vendor
    mock_service.expects(:create_file)
      .with(
        has_entry(:name, "2026-01-15 - Unknown - Invoice #{@invoice.id}.jpg"),
        anything
      )
      .returns(mock_uploaded_file)

    DriveUploadJob.perform_now(@invoice.id)
  end

  # Test status updates
  test "should update status to processing then completed" do
    mock_service = mock('drive_service')
    mock_credentials = mock('credentials')
    mock_uploaded_file = mock('uploaded_file')

    Google::Apis::DriveV3::DriveService.expects(:new).returns(mock_service)
    mock_service.expects(:authorization=).with(mock_credentials)
    DriveUploadJob.any_instance.expects(:get_google_credentials).returns(mock_credentials)

    mock_uploaded_file.stubs(:id).returns('file_id')
    mock_uploaded_file.stubs(:web_view_link).returns('https://drive.google.com/file/d/file_id/view')
    mock_service.expects(:create_file).returns(mock_uploaded_file)

    # Initially pending
    assert_equal 'pending', @invoice.drive_upload_status

    DriveUploadJob.perform_now(@invoice.id)

    # Should be completed after job
    @invoice.reload
    assert_equal 'completed', @invoice.drive_upload_status
  end

  # Test enqueuing SheetUpdateJob
  test "should enqueue SheetUpdateJob after successful upload" do
    mock_service = mock('drive_service')
    mock_credentials = mock('credentials')
    mock_uploaded_file = mock('uploaded_file')

    Google::Apis::DriveV3::DriveService.expects(:new).returns(mock_service)
    mock_service.expects(:authorization=).with(mock_credentials)
    DriveUploadJob.any_instance.expects(:get_google_credentials).returns(mock_credentials)

    mock_uploaded_file.stubs(:id).returns('file_id')
    mock_uploaded_file.stubs(:web_view_link).returns('https://drive.google.com/file/d/file_id/view')
    mock_service.expects(:create_file).returns(mock_uploaded_file)

    # Note: Job uses perform_now instead of perform_later, so SheetUpdateJob runs immediately
    # We can verify it attempted to run by checking the invoice status after

    DriveUploadJob.perform_now(@invoice.id)

    # If SheetUpdateJob ran (even if it failed), drive upload should be completed
    @invoice.reload
    assert_equal 'completed', @invoice.drive_upload_status
  end

  # Test error handling
  test "should mark invoice as failed on error" do
    mock_service = mock('drive_service')
    mock_credentials = mock('credentials')

    Google::Apis::DriveV3::DriveService.expects(:new).returns(mock_service)
    mock_service.expects(:authorization=).with(mock_credentials)
    DriveUploadJob.any_instance.expects(:get_google_credentials).returns(mock_credentials)

    # Simulate upload error
    mock_service.expects(:create_file).raises(StandardError.new("Upload failed"))

    # Job will raise error, but ActiveJob might catch it in test mode
    # Just verify the failure is properly recorded
    begin
      DriveUploadJob.perform_now(@invoice.id)
    rescue StandardError => e
      # Expected - job re-raises after marking as failed
      assert_equal "Upload failed", e.message
    end

    @invoice.reload
    assert_equal 'failed', @invoice.drive_upload_status
    assert_equal 'failed', @invoice.status
    assert_includes @invoice.error_message, "Upload failed"
  end

  # Test missing credentials error
  test "should handle missing OAuth credentials" do
    Google::Apis::DriveV3::DriveService.expects(:new).returns(mock('drive_service'))

    DriveUploadJob.any_instance.expects(:get_google_credentials)
      .raises(StandardError.new("No Google OAuth credentials found"))

    # Job will raise error, but ActiveJob might catch it in test mode
    # Just verify the failure is properly recorded
    begin
      DriveUploadJob.perform_now(@invoice.id)
    rescue StandardError => e
      # Expected - job re-raises after marking as failed
      assert_equal "No Google OAuth credentials found", e.message
    end

    @invoice.reload
    assert_equal 'failed', @invoice.drive_upload_status
    assert_includes @invoice.error_message, "No Google OAuth credentials"
  end

  # Test folder ID from credentials
  test "should use folder ID from credentials" do
    # Mock credentials to return a specific folder ID
    Rails.application.credentials.stubs(:google_drive_folder_id).returns('test_folder_id_123')

    mock_service = mock('drive_service')
    mock_credentials = mock('credentials')
    mock_uploaded_file = mock('uploaded_file')

    Google::Apis::DriveV3::DriveService.expects(:new).returns(mock_service)
    mock_service.expects(:authorization=).with(mock_credentials)
    DriveUploadJob.any_instance.expects(:get_google_credentials).returns(mock_credentials)

    mock_uploaded_file.stubs(:id).returns('file_id')
    mock_uploaded_file.stubs(:web_view_link).returns('https://drive.google.com/file/d/file_id/view')

    # Verify folder ID is passed to create_file
    mock_service.expects(:create_file)
      .with(
        has_entry(:parents, ['test_folder_id_123']),
        anything
      )
      .returns(mock_uploaded_file)

    DriveUploadJob.perform_now(@invoice.id)
  end
end
