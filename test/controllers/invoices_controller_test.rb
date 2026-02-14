require "test_helper"

class InvoicesControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Clean up any existing invoices to ensure test isolation
    Invoice.destroy_all

    # Stub the InvoiceParser to avoid calling Anthropic API in tests
    InvoiceParser.any_instance.stubs(:parse).returns({
      "date" => "1-Jan-2025",
      "particulars" => "Test Vendor",
      "type" => "Business Expense",
      "classification" => "Office Supplies",
      "description" => "Test description",
      "amount_inr" => "1000",
      "amount_usd" => "12",
      "mode_of_transaction" => "Credit Card"
    })
  end

  # Test GET #new
  test "should get new invoice form" do
    get new_invoice_url
    assert_response :success
    assert_select "form[action=?]", invoices_path
  end

  # Test POST #create with valid parameters
  test "should create invoice with valid image and parse immediately" do
    file = fixture_file_upload('test_invoice.png', 'image/png')

    assert_difference('Invoice.count', 1) do
      post invoices_url, params: { invoice: { image: file } }
    end

    invoice = Invoice.last
    assert invoice.image.attached?, "Image should be attached"
    assert_equal 'processing', invoice.status
    assert_equal 'completed', invoice.parsing_status
    assert_not_empty invoice.extracted_data
    assert_redirected_to invoice_path(invoice)
  end

  # Test POST #create with invalid parameters
  test "should not create invoice without image" do
    assert_no_difference('Invoice.count') do
      post invoices_url, params: { invoice: { image: nil } }
    end

    assert_response :unprocessable_entity
  end

  # Test GET #show
  test "should show invoice with extracted data" do
    invoice = Invoice.create!(
      image: fixture_file_upload('test_invoice.png', 'image/png'),
      status: 'processing',
      parsing_status: 'completed',
      extracted_data: {
        "date" => "1-Jan-2025",
        "particulars" => "Test Vendor"
      }
    )

    get invoice_url(invoice)
    assert_response :success
    assert_select "input[value=?]", "Test Vendor"
  end

  # Test PATCH #update
  test "should update invoice and enqueue background jobs" do
    invoice = Invoice.create!(
      image: fixture_file_upload('test_invoice.png', 'image/png'),
      status: 'processing',
      parsing_status: 'completed',
      extracted_data: { "particulars" => "Old Vendor" }
    )

    assert_enqueued_with(job: DriveUploadJob) do
      patch invoice_url(invoice), params: {
        invoice: {
          extracted_data: {
            date: "2-Feb-2025",
            particulars: "Updated Vendor",
            type: "Business Expense"
          }
        }
      }
    end

    invoice.reload
    assert_equal "Updated Vendor", invoice.extracted_data["particulars"]
    assert_redirected_to invoice_path(invoice)
  end

  # Test GET #thank_you (legacy page)
  test "should get thank you page" do
    get thank_you_invoices_url
    assert_response :success
  end
end
