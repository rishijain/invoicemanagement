require 'base64'
require 'image_processing/mini_magick'

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
    Rails.logger.info "📸 Parsing invoice image ##{invoice.id} with Claude..."

    # Initialize Anthropic client
    client = Anthropic::Client.new(
      api_key: Rails.application.credentials.anthropic_api_key
    )

    # Get image data and convert HEIC to JPEG if needed
    content_type = invoice.image.content_type || "image/jpeg"
    base64_image = nil
    media_type = nil

    if content_type =~ /heic|heif/i
      # Convert HEIC to JPEG with compression
      Rails.logger.info "  Converting HEIC to JPEG with compression..."
      invoice.image.open do |file|
        processed = ImageProcessing::MiniMagick
          .source(file)
          .convert("jpeg")
          .resize_to_limit(2000, 2000)  # Compress to prevent API timeouts
          .call

        image_data = File.read(processed.path)
        base64_image = Base64.strict_encode64(image_data)
      end
      media_type = "image/jpeg"
    else
      # Use image with compression to prevent API timeouts
      Rails.logger.info "  Compressing image..."
      invoice.image.open do |file|
        processed = ImageProcessing::MiniMagick
          .source(file)
          .resize_to_limit(2000, 2000)  # Compress large images
          .call

        image_data = File.read(processed.path)
        base64_image = Base64.strict_encode64(image_data)
      end

      # Determine media type
      media_type = case content_type
                   when /jpeg|jpg/i
                     "image/jpeg"
                   when /png/i
                     "image/png"
                   when /gif/i
                     "image/gif"
                   when /webp/i
                     "image/webp"
                   else
                     "image/jpeg"
                   end
    end

    # Call Claude API with vision (using Haiku - fast and cost-effective)
    response = client.messages.create(
      model: "claude-3-haiku-20240307",
      max_tokens: 2048,
      messages: [
          {
            role: "user",
            content: [
              {
                type: "image",
                source: {
                  type: "base64",
                  media_type: media_type,
                  data: base64_image
                }
              },
              {
                type: "text",
                text: <<~PROMPT
                  Extract the following information from this invoice or receipt image.
                  Return ONLY a valid JSON object with these exact fields (use null for missing values):

                  {
                    "vendor_name": "name of the vendor/merchant",
                    "invoice_number": "invoice or receipt number",
                    "date": "date in YYYY-MM-DD format",
                    "total_amount": numeric value only,
                    "tax_amount": numeric value only,
                    "currency": "3-letter currency code like USD, EUR, INR"
                  }

                  Do not include any explanation, only the JSON object.
                PROMPT
              }
            ]
          }
        ]
    )

    # Extract text from response (response is an Anthropic::Models::Message object)
    text_content = response.content[0].text

    # Parse JSON response
    extracted_data = JSON.parse(text_content)

    # Add metadata
    extracted_data["parsed_at"] = Time.current.to_s

    Rails.logger.info "✅ Successfully parsed invoice ##{invoice.id}"

    extracted_data
  rescue JSON::ParserError => e
    Rails.logger.error "Failed to parse JSON response: #{e.message}"
    Rails.logger.error "Response was: #{text_content}"
    raise "LLM returned invalid JSON: #{e.message}"
  rescue StandardError => e
    Rails.logger.error "Failed to parse invoice: #{e.message}"
    raise
  end
end
