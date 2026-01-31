require "test_helper"

class InvoicesControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Clean up any existing invoices to ensure test isolation
    Invoice.destroy_all
  end

  # Test GET #new
  test "should get new invoice form" do
    get new_invoice_url
    assert_response :success
    assert_select "form[action=?]", invoices_path
  end


  # Test POST #create with valid parameters
  test "should create invoice with valid image" do
    # Create a test file upload
    file = fixture_file_upload('test_invoice.png', 'image/png')

    assert_difference('Invoice.count', 1) do
      post invoices_url, params: { invoice: { image: file } }
    end

    invoice = Invoice.last
    assert invoice.image.attached?, "Image should be attached"
    assert_equal 'pending', invoice.status
    assert_redirected_to thank_you_invoices_path
    assert_equal 'Invoice uploaded successfully!', flash[:notice]
  end

  test "should enqueue ImageParsingJob when invoice is created" do
    file = fixture_file_upload('test_invoice.png', 'image/png')

    assert_enqueued_with(job: ImageParsingJob) do
      post invoices_url, params: { invoice: { image: file } }
    end
    invoice = Invoice.last
    assert_not_nil invoice
  end

  # Test POST #create with invalid parameters
  test "should not create invoice without image" do
    assert_no_difference('Invoice.count') do
      post invoices_url, params: { invoice: { image: nil } }
    end

    assert_response :unprocessable_entity
  end

  test "should not enqueue job when invoice creation fails" do
    assert_no_enqueued_jobs(only: ImageParsingJob) do
      post invoices_url, params: { invoice: { image: nil } }
    end
  end

  test "should render errors when image is missing" do
    post invoices_url, params: { invoice: { image: nil } }

    assert_response :unprocessable_entity
    # Verify the invoice wasn't created due to validation failure
    assert_equal 0, Invoice.count
  end

  # Test GET #thank_you
  test "should get thank you page" do
    get thank_you_invoices_url
    assert_response :success
  end

  # Integration tests
  test "complete upload flow creates invoice and enqueues job" do
    file = fixture_file_upload('test_invoice.png', 'image/png')

    # Should create invoice
    assert_difference('Invoice.count', 1) do
      # Should enqueue job
      assert_enqueued_with(job: ImageParsingJob) do
        post invoices_url, params: { invoice: { image: file } }
      end
    end

    # Should redirect to thank you page
    assert_redirected_to thank_you_invoices_path
    follow_redirect!
    assert_response :success
  end

  test "created invoice should have correct initial status values" do
    file = fixture_file_upload('test_invoice.png', 'image/png')
    post invoices_url, params: { invoice: { image: file } }

    invoice = Invoice.last
    assert_equal 'pending', invoice.status
    assert_equal 'pending', invoice.parsing_status
    assert_equal 'pending', invoice.drive_upload_status
    assert_equal 'pending', invoice.sheet_update_status
    assert_nil invoice.error_message
    assert_nil invoice.processed_at
    assert_equal({}, invoice.extracted_data)
  end
end
