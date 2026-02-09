class InvoicesController < ApplicationController
  def new
    @invoice = Invoice.new
  end

  def create
    @invoice = Invoice.new(invoice_params)
    @invoice.status = 'pending'

    if @invoice.save
      # Enqueue the first job in the processing chain (delayed by 15 seconds)
      ImageParsingJob.set(wait: 2.seconds).perform_later(@invoice.id)

      redirect_to thank_you_invoices_path, notice: 'Invoice uploaded successfully!'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def thank_you
  end

  private

  def invoice_params
    params.require(:invoice).permit(:image, :manual_date)
  end
end
