class InvoicesController < ApplicationController
  def new
    @invoice = Invoice.new
  end

  def create
    @invoice = Invoice.new(invoice_params)
    @invoice.status = 'processing'

    if @invoice.save
      begin
        # Parse invoice immediately (synchronous)
        parser = InvoiceParser.new(@invoice)
        extracted_data = parser.parse

        # Save extracted data
        @invoice.update!(
          extracted_data: extracted_data,
          parsing_status: 'completed'
        )

        redirect_to invoice_path(@invoice), notice: 'Invoice uploaded and processed successfully! Please review the extracted data.'
      rescue StandardError => e
        @invoice.update(
          parsing_status: 'failed',
          error_message: e.message
        )
        redirect_to new_invoice_path, alert: "Failed to process invoice: #{e.message}"
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @invoice = Invoice.find(params[:id])
  end

  def update
    @invoice = Invoice.find(params[:id])

    if @invoice.update(invoice_update_params)
      # Mark as ready for upload and enqueue background jobs
      @invoice.update!(status: 'processing')

      # Enqueue Drive upload (which will then enqueue Sheet update)
      DriveUploadJob.perform_later(@invoice.id)

      redirect_to invoice_path(@invoice), notice: 'Invoice saved and queued for upload to Google Drive and Sheets!'
    else
      render :show, status: :unprocessable_entity
    end
  end

  def thank_you
  end

  private

  def invoice_params
    params.require(:invoice).permit(:image)
  end

  def invoice_update_params
    params.require(:invoice).permit(
      extracted_data: [
        :date,
        :particulars,
        :type,
        :classification,
        :description,
        :amount_inr,
        :amount_usd,
        :mode_of_transaction
      ]
    )
  end
end
