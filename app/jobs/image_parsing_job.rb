class ImageParsingJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: 5.seconds, attempts: 3

  def perform(invoice_id)
    invoice = Invoice.find(invoice_id)

    # Skip if already completed (idempotent)
    return if invoice.parsing_completed?

    # Update status to processing
    invoice.update!(status: 'processing', parsing_status: 'processing')

    # TODO: Replace with actual LLM API call
    # For now, use stub data
    extracted_data = parse_invoice_with_llm(invoice)

    # Mark parsing complete and save extracted data
    invoice.mark_parsing_complete!(extracted_data)

    # Enqueue next job in the chain
    DriveUploadJob.perform_later(invoice.id)

  rescue StandardError => e
    invoice.mark_step_failed!('parsing', e.message)
    raise # Re-raise to trigger retry
  end

  private

  def parse_invoice_with_llm(invoice)
    # STUB: This will be replaced with actual Anthropic Claude API call
    # For now, return mock data
    Rails.logger.info "📸 [STUB] Parsing image for invoice ##{invoice.id}"

    {
      vendor_name: "Sample Vendor",
      invoice_number: "INV-#{rand(1000..9999)}",
      date: Date.today.to_s,
      total_amount: rand(100..1000).round(2),
      tax_amount: rand(10..100).round(2),
      currency: "USD",
      parsed_at: Time.current.to_s
    }
  end
end
