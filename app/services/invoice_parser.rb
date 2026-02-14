require 'base64'
require 'image_processing/mini_magick'

class InvoiceParser
  def initialize(invoice)
    @invoice = invoice
  end

  def parse
    Rails.logger.info "📸 Parsing invoice image ##{@invoice.id} with Claude..."

    # Initialize Anthropic client
    client = Anthropic::Client.new(
      api_key: ENV['ANTHROPIC_API_KEY'] || Rails.application.credentials.anthropic_api_key
    )

    # Get image data and convert HEIC to JPEG if needed
    content_type = @invoice.image.content_type || "image/jpeg"
    base64_image = nil
    media_type = nil

    if content_type =~ /heic|heif/i
      # Convert HEIC to JPEG with compression
      Rails.logger.info "  Converting HEIC to JPEG with compression..."
      @invoice.image.open do |file|
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
      @invoice.image.open do |file|
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
                  Carefully analyze this invoice or receipt image and extract the following information.

                  IMPORTANT for date extraction:
                  - Look for the INVOICE DATE or BILL DATE (not expiry date, order date, or validity date)
                  - This is typically labeled as "Date:", "Invoice Date:", "Bill Date:", or similar
                  - It represents when the transaction occurred

                  Return ONLY a valid JSON object with these exact fields (use null for missing values):

                  {
                    "particulars": "name of the company/restaurant/vendor",
                    "date": "the invoice/bill date in YYYY-MM-DD format",
                    "total_amount": numeric value only (the final amount to be paid),
                    "currency": "3-letter currency code like USD, EUR, INR",
                    "invoice_type": "classify as either 'restaurant' (for food/dining bills) or 'travel' (for transportation, hotels, flights) or 'other'"
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

    # Convert LLM-extracted date to D-MMM-YYYY format (e.g., 1-Apr-2025)
    if extracted_data["date"].present?
      begin
        parsed_date = Date.parse(extracted_data["date"])
        extracted_data["date"] = parsed_date.strftime("%-d-%b-%Y")
        Rails.logger.info "   Using LLM-extracted date: #{extracted_data['date']}"
      rescue Date::Error => e
        Rails.logger.warn "Could not parse date: #{extracted_data['date']}"
        # Keep original date if parsing fails
      end
    end

    # Set amount in the correct currency field
    currency = extracted_data["currency"]&.upcase
    total_amount = extracted_data["total_amount"]

    if currency == "INR"
      extracted_data["amount_inr"] = total_amount
      extracted_data["amount_usd"] = nil
    elsif currency == "USD"
      extracted_data["amount_usd"] = total_amount
      extracted_data["amount_inr"] = nil
    else
      # For other currencies, default to INR field
      extracted_data["amount_inr"] = total_amount
      extracted_data["amount_usd"] = nil
    end

    # Apply business rules
    extracted_data["type"] = "debit"
    extracted_data["mode_of_transaction"] = "rishi paid for it"

    # Set classification and description based on invoice type
    case extracted_data["invoice_type"]
    when "restaurant"
      extracted_data["classification"] = "office"
      extracted_data["description"] = "meeting with client"
    when "travel"
      extracted_data["classification"] = "travel"
      extracted_data["description"] = "travel for meeting"
    else
      extracted_data["classification"] = "other"
      extracted_data["description"] = nil
    end

    # Add metadata
    extracted_data["parsed_at"] = Time.current.to_s

    Rails.logger.info "✅ Successfully parsed invoice ##{@invoice.id}"
    Rails.logger.info "   Classification: #{extracted_data['classification']}, Type: #{extracted_data['type']}"

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
