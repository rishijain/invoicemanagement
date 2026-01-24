# Invoice Manager - Technical Documentation

## Project Overview

A Rails 8 application that automatically processes invoice and receipt images using AI and cloud services.

**Tech Stack:**
- Rails 8.1.2
- Ruby 3.3.6
- PostgreSQL 16
- Solid Queue (background jobs)
- Active Storage (file uploads)
- Anthropic Claude API (AI/LLM)
- Google Drive API (file storage) - *in progress*
- Google Sheets API (data storage) - *in progress*

**Purpose:**
Users upload invoice/receipt images via web form → AI extracts data → Uploads to Google Drive → Appends to Google Sheet

---

## Architecture

### Job Processing Pipeline

```
User Upload (web form)
    ↓
Invoice saved to database
Active Storage stores image file
    ↓
ImageParsingJob enqueued
    ↓
┌─────────────────────────────────┐
│ ImageParsingJob                 │
│ - Converts HEIC → JPEG if needed│
│ - Sends to Claude API           │
│ - Extracts: vendor, invoice #,  │
│   date, amount, tax, currency   │
│ - Updates invoice.extracted_data│
│ - Status: parsing → completed   │
└─────────────────────────────────┘
    ↓ (enqueues next job)
┌─────────────────────────────────┐
│ DriveUploadJob                  │
│ - Uploads image to Google Drive │
│ - Gets shareable URL            │
│ - Saves URL to invoice          │
│ - Status: drive_upload → done   │
└─────────────────────────────────┘
    ↓ (enqueues next job)
┌─────────────────────────────────┐
│ SheetUpdateJob                  │
│ - Appends row to Google Sheet   │
│ - Includes extracted data + URL │
│ - Status: sheet_update → done   │
│ - Overall status → completed    │
└─────────────────────────────────┘
```

---

## Database Schema

### Invoices Table

```ruby
create_table :invoices do |t|
  t.string :status, default: 'pending'  # overall: pending, processing, completed, failed

  # Step-by-step status tracking
  t.string :parsing_status, default: 'pending'
  t.string :drive_upload_status, default: 'pending'
  t.string :sheet_update_status, default: 'pending'

  # Extracted data from LLM
  t.jsonb :extracted_data, default: {}
  # Example: {vendor_name, invoice_number, date, total_amount, tax_amount, currency}

  # Google Drive results
  t.string :google_drive_url
  t.string :google_drive_file_id

  # Google Sheets results
  t.integer :google_sheet_row_number

  # Error tracking
  t.text :error_message
  t.datetime :processed_at

  t.timestamps
end
```

**Active Storage Attachment:**
- `invoice.image` - The uploaded invoice/receipt image (JPEG, PNG, HEIC, etc.)

---

## File Structure

```
app/
├── controllers/
│   └── invoices_controller.rb    # Handles upload form and create
├── jobs/
│   ├── image_parsing_job.rb      # LLM parsing (IMPLEMENTED)
│   ├── drive_upload_job.rb       # Google Drive upload (STUB)
│   └── sheet_update_job.rb       # Google Sheets append (STUB)
├── models/
│   └── invoice.rb                # Invoice model with status enums
└── views/
    └── invoices/
        ├── new.html.erb          # Upload form
        └── thank_you.html.erb    # Success page

config/
├── credentials.yml.enc           # Encrypted: anthropic_api_key
├── database.yml                  # PostgreSQL + Solid Queue config
├── storage.yml                   # Active Storage config
└── routes.rb                     # Root: invoices#new

db/
├── schema.rb                     # Main database schema
└── queue_schema.rb               # Solid Queue tables
```

---

## Setup Instructions

### Prerequisites

```bash
# Ruby 3.3.6
ruby -v

# PostgreSQL 16
brew install postgresql@16
brew services start postgresql@16

# ImageMagick (for HEIC conversion)
brew install imagemagick

# Rails 8
gem install rails -v '~> 8.0'
```

### Installation

```bash
# Clone and setup
cd /Users/riru/projects/invoicemanager
bundle install

# Database setup
bin/rails db:create
bin/rails db:migrate
bin/rails db:schema:load:queue  # Load Solid Queue tables

# Start services
bin/rails server              # Terminal 1: Rails server (port 3000)
bin/jobs                      # Terminal 2: Solid Queue worker
```

### Configuration

**1. Anthropic API Key:**
```bash
# Edit encrypted credentials
EDITOR="nano" bin/rails credentials:edit

# Add this line:
anthropic_api_key: sk-ant-api03-YOUR-KEY-HERE
```

**2. Google Service Account (TODO):**
- Create Google Cloud Project
- Enable Google Drive API & Google Sheets API
- Create Service Account
- Download JSON credentials
- Store in: `config/google_credentials.json` (add to .gitignore)

**3. Google Drive & Sheets IDs (TODO):**
```bash
# Add to credentials:
google_drive_folder_id: YOUR_FOLDER_ID
google_sheet_id: YOUR_SHEET_ID
google_sheet_tab_name: Sheet1
```

---

## API Integration Details

### Anthropic Claude API

**Current Model:** `claude-3-haiku-20240307`
- Fast and cost-effective (~$0.001-0.003 per invoice)
- Good accuracy for structured document parsing
- Supports vision (image input)

**Prompt Strategy:**
- Request JSON-only output (no explanation)
- Specify exact field names
- Handle null values for missing data

**Image Processing:**
- Accepts: JPEG, PNG, GIF, WebP
- Auto-converts HEIC (iPhone photos) to JPEG
- Base64 encodes images for API transmission

**Error Handling:**
- 3 retry attempts with 5-second delay
- Saves error messages to `invoice.error_message`
- Marks `parsing_status` as 'failed'

### Google Drive API (TODO)

**Implementation Plan:**
```ruby
# In DriveUploadJob
require 'google/apis/drive_v3'

def upload_to_google_drive(invoice)
  service = Google::Apis::DriveV3::DriveService.new
  service.authorization = get_credentials

  invoice.image.open do |file|
    metadata = { name: invoice.image.filename.to_s }
    file_object = service.create_file(
      metadata,
      fields: 'id, webViewLink',
      upload_source: file.path,
      content_type: 'image/jpeg'
    )

    # Make publicly viewable
    permission = { type: 'anyone', role: 'reader' }
    service.create_permission(file_object.id, permission)

    [file_object.web_view_link, file_object.id]
  end
end
```

### Google Sheets API (TODO)

**Implementation Plan:**
```ruby
# In SheetUpdateJob
require 'google/apis/sheets_v4'

def append_to_google_sheet(invoice)
  service = Google::Apis::SheetsV4::SheetsService.new
  service.authorization = get_credentials

  # Prepare row data
  row = [
    invoice.extracted_data['date'],
    invoice.extracted_data['vendor_name'],
    invoice.extracted_data['invoice_number'],
    invoice.extracted_data['total_amount'],
    invoice.extracted_data['tax_amount'],
    invoice.extracted_data['currency'],
    invoice.google_drive_url,
    Time.current.to_s
  ]

  # Append to sheet
  range = "#{sheet_tab_name}!A:H"
  value_range = Google::Apis::SheetsV4::ValueRange.new(values: [row])
  result = service.append_spreadsheet_value(
    sheet_id,
    range,
    value_range,
    value_input_option: 'USER_ENTERED'
  )

  result.updates.updated_range.split('!')[1].split(':')[0].scan(/\d+/)[0].to_i
end
```

---

## Running Jobs

### Start Background Worker

```bash
bin/jobs
```

**What it does:**
- Polls Solid Queue database for pending jobs
- Executes jobs in separate threads
- Auto-retries failed jobs (3 attempts)
- Logs to `log/development.log`

**Important:**
- Must restart after code changes (doesn't auto-reload like Rails server)
- Can run multiple workers for parallel processing
- Uses PostgreSQL for job queue (no Redis needed)

### Manual Job Execution (for testing)

```bash
# Run job synchronously (for debugging)
bin/rails runner "ImageParsingJob.perform_now(invoice_id)"

# Check job status
bin/rails runner "
  SolidQueue::Job.where(class_name: 'ImageParsingJob').each do |job|
    puts \"Job ##{job.id}: #{job.finished_at ? 'Completed' : 'Pending'}\"
  end
"

# Check failed jobs
bin/rails runner "
  SolidQueue::FailedExecution.last(5).each do |f|
    puts \"#{f.job.class_name}: #{f.error['message']}\"
  end
"
```

---

## Model Methods

### Invoice Model

**Status Enums:**
```ruby
# Overall status
invoice.status_pending?
invoice.status_processing?
invoice.status_completed?
invoice.status_failed?

# Step status
invoice.parsing_completed?
invoice.drive_upload_completed?
invoice.sheet_update_completed?
```

**Helper Methods:**
```ruby
# Mark steps complete
invoice.mark_parsing_complete!(data_hash)
invoice.mark_drive_upload_complete!(url, file_id)
invoice.mark_sheet_update_complete!(row_number)

# Mark step failed
invoice.mark_step_failed!('parsing', error_message)

# Check completion
invoice.all_steps_completed?  # => true/false
```

**Scopes:**
```ruby
Invoice.ready_for_parsing
Invoice.ready_for_drive_upload
Invoice.ready_for_sheet_update
Invoice.fully_completed
```

---

## Testing

### Upload a Test Invoice

```bash
# Start services
bin/rails server  # Terminal 1
bin/jobs          # Terminal 2

# Visit http://localhost:3000
# Upload an invoice/receipt image
# Check progress in Terminal 2 logs
```

### Check Invoice Status

```ruby
bin/rails console

# Get latest invoice
invoice = Invoice.last

# Check status
invoice.status                    # => "completed"
invoice.parsing_status            # => "completed"
invoice.extracted_data           # => {vendor_name: "...", ...}
invoice.google_drive_url         # => "https://drive.google.com/..."
invoice.google_sheet_row_number  # => 42

# Check for errors
invoice.error_message  # => nil if successful
```

---

## Troubleshooting

### Jobs Not Processing

**Problem:** Invoice stays in `pending` status

**Solutions:**
1. Check if `bin/jobs` is running
2. Restart `bin/jobs` after code changes
3. Check for failed jobs:
   ```bash
   bin/rails runner "
     SolidQueue::FailedExecution.last&.error
   "
   ```

### HEIC Conversion Fails

**Problem:** `cannot convert HEIC`

**Solutions:**
1. Ensure ImageMagick installed: `brew install imagemagick`
2. Check libheif support: `magick -list format | grep HEIC`
3. If missing: `brew reinstall imagemagick`

### Anthropic API Errors

**Problem:** API returns 404 or 400 errors

**Solutions:**
1. **404 (model not found):** Check model name and account access
2. **400 (credit balance):** Add credits at console.anthropic.com
3. **401 (unauthorized):** Verify API key in credentials
4. **Invalid format:** Check image type (HEIC gets converted automatically)

### Database Issues

**Problem:** `queue database not configured`

**Solution:** Run schema load:
```bash
bin/rails db:schema:load:queue
```

---

## Logs and Monitoring

### View Logs

```bash
# Follow all logs
tail -f log/development.log

# Filter for jobs
tail -f log/development.log | grep -E "ImageParsing|DriveUpload|SheetUpdate"

# Filter for errors
tail -f log/development.log | grep -i error

# Watch Solid Queue worker (Terminal 2 where bin/jobs runs)
# Shows job execution in real-time
```

### Check Job Queue

```bash
# Pending jobs
bin/rails runner "
  puts SolidQueue::Job.where(finished_at: nil).count
"

# Failed jobs
bin/rails runner "
  SolidQueue::FailedExecution.order(created_at: :desc).limit(5).each do |f|
    puts \"#{f.job.class_name}: #{f.error['message']}\"
  end
"
```

---

## Security

### Secrets Management

**Stored in Rails Encrypted Credentials:**
- `anthropic_api_key` - Anthropic API key (sk-ant-api03-...)
- `google_credentials` - Google Service Account JSON (TODO)
- Master key in: `config/master.key` (NOT in git)

**Edit Credentials:**
```bash
EDITOR="nano" bin/rails credentials:edit
```

### .gitignore Protection

**Already ignored:**
- `config/master.key`
- `config/*.key`
- `.env*`
- `storage/*` (uploaded images)
- `tmp/*`
- `log/*`

**Safe to commit:**
- `config/credentials.yml.enc` (encrypted)
- All code files (use Rails.application.credentials)

---

## Current Status

### ✅ Implemented
- Rails 8 app with PostgreSQL
- Active Storage for image uploads
- Solid Queue background jobs
- Invoice model with detailed status tracking
- ImageParsingJob with Claude API integration
- HEIC to JPEG automatic conversion
- Job chain architecture (3 jobs)
- Web UI for uploads
- Status tracking per step

### 🚧 In Progress (Stubs)
- DriveUploadJob - Returns mock URL
- SheetUpdateJob - Logs mock data

### 📋 TODO
1. Implement Google Drive API in DriveUploadJob
2. Implement Google Sheets API in SheetUpdateJob
3. Add Google Service Account credentials
4. Configure Drive folder ID and Sheet ID
5. Define Sheet column structure
6. Add user dashboard to view processed invoices (optional)
7. Add retry/reprocess UI (optional)
8. Add invoice viewing page (optional)

---

## Environment Variables

**Current Setup:** Using Rails encrypted credentials

**Alternative:** Create `.env` file (for local dev)
```bash
ANTHROPIC_API_KEY=sk-ant-api03-...
GOOGLE_DRIVE_FOLDER_ID=...
GOOGLE_SHEET_ID=...
```

Then add to Gemfile: `gem 'dotenv-rails'`

---

## Deployment Considerations

### Production Checklist

- [ ] Add production database password to credentials
- [ ] Configure production Active Storage (S3, GCS, etc.)
- [ ] Scale Solid Queue workers (multiple processes)
- [ ] Set up monitoring/alerting for failed jobs
- [ ] Configure CORS if needed for uploads
- [ ] Add rate limiting for uploads
- [ ] Set up SSL/HTTPS
- [ ] Configure proper logging (not debug level)
- [ ] Add health check endpoint for workers

### Kamal Deployment

App includes Kamal configuration:
```bash
bin/kamal setup
bin/kamal deploy
```

---

## Useful Commands

```bash
# Database
bin/rails db:reset              # Drop, create, migrate
bin/rails db:seed              # Load seed data (if any)

# Console
bin/rails console              # Interactive Ruby console

# Routes
bin/rails routes | grep invoice

# Check model
bin/rails runner "Invoice.column_names"

# Clear failed jobs
bin/rails runner "SolidQueue::FailedExecution.delete_all"

# Clear all jobs
bin/rails runner "SolidQueue::Job.delete_all"

# Reset invoice
bin/rails runner "
  invoice = Invoice.last
  invoice.update(
    status: 'pending',
    parsing_status: 'pending',
    drive_upload_status: 'pending',
    sheet_update_status: 'pending',
    error_message: nil
  )
"
```

---

## Cost Estimates

**Anthropic API:**
- Claude 3 Haiku: ~$0.001-0.003 per invoice
- 1000 invoices ≈ $1-3

**Google Drive:**
- 15GB free, then $1.99/month for 100GB
- Images ~500KB-2MB each

**Google Sheets:**
- Free (API quotas are generous)

**Hosting:**
- Depends on provider (Heroku, Fly.io, AWS, etc.)

---

## Contributing

When making changes:

1. **Always check for sensitive data before committing:**
   ```bash
   git diff | grep -i "api_key\|password\|secret"
   ```

2. **Use Rails credentials for secrets:**
   ```ruby
   # Good
   Rails.application.credentials.anthropic_api_key

   # Bad
   api_key = "sk-ant-api03-..."
   ```

3. **Restart bin/jobs after code changes**

4. **Test the full pipeline:**
   - Upload → ImageParsingJob → DriveUploadJob → SheetUpdateJob

5. **Update this CLAUDE.md file when adding features**

---

## Contact & Support

**Project Location:** `/Users/riru/projects/invoicemanager`

**Git Repository:** (add URL when pushed)

**Created:** January 2026

**Last Updated:** January 24, 2026
