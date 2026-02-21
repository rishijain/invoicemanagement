# Invoice Manager - Technical Documentation

**Last Updated:** February 2026
**Status:** ✅ Fully Functional in Production

## ⚠️ Important Notes for Developers

1. **Parsing is SYNCHRONOUS** - No ImageParsingJob! Parsing happens in the controller via `InvoiceParser` service
2. **User reviews data BEFORE upload** - Show page displays editable form, background jobs run ONLY after user clicks Save
3. **OAuth not Service Account** - Uses Google OAuth2 with refresh token (authorize locally, copy to production)
4. **No manual_date field** - Was removed, AI extracts all dates
5. **Business rules are hardcoded** - type="debit", mode_of_transaction defaults, classification based on invoice_type
6. **Force push recovery** - Use `git reset --hard origin/main` if divergent branches after force push

---

## Project Overview

A Rails 8 application that automatically processes invoice and receipt images using AI and cloud services.

**Tech Stack:**
- Rails 8.1.2
- Ruby 3.3.6
- PostgreSQL 16
- Solid Queue (background jobs)
- Active Storage (file uploads)
- Anthropic Claude API (AI/LLM)
- Google Drive API (file storage) - ✅ IMPLEMENTED
- Google Sheets API (data storage) - ✅ IMPLEMENTED

**Purpose:**
Users upload invoice/receipt images via web form → AI extracts data immediately → User reviews/edits data → Uploads to Google Drive → Appends to Google Sheet

---

## Quick Start (Development)

```bash
# Start Rails server
bin/rails server

# Start background workers (separate terminal)
bin/jobs

# Visit http://localhost:3000
# Upload an invoice → Review extracted data → Save → Jobs process in background
```

## Key Concepts

### Synchronous vs Asynchronous Processing

**Parsing (SYNCHRONOUS):**
- Happens immediately when user uploads
- Uses `InvoiceParser` service in controller
- User sees results right away on show page
- Can edit any extracted field before saving

**Upload to Drive/Sheets (ASYNCHRONOUS):**
- Happens ONLY after user confirms data
- Uses background jobs: `DriveUploadJob` → `SheetUpdateJob`
- Runs in Solid Queue workers
- User can close browser after clicking Save

### Business Rules (Auto-Applied)

The system automatically applies these rules during parsing:

1. **Type**: Always set to "debit"
2. **Mode of Transaction**: Default "rishi paid for it" (user can change to "rupali paid for it" or "paid via company account")
3. **Classification & Description**: Based on invoice type
   - Restaurant → "office" + "meeting with client"
   - Travel → "travel" + "travel for meeting"
   - Other → "other" + null
4. **Currency Handling**: Splits amount into INR or USD based on detected currency

---

## Architecture

### Processing Pipeline (Current)

```
1. User Upload (web form)
    ↓
2. Invoice saved to database + Active Storage stores image
    ↓
3. InvoiceParser Service (SYNCHRONOUS - in controller)
   ┌─────────────────────────────────┐
   │ InvoiceParser.parse             │
   │ - Converts HEIC → JPEG if needed│
   │ - Compresses image (2000x2000)  │
   │ - Sends to Claude API           │
   │ - Extracts: date, particulars,  │
   │   type, classification,         │
   │   description, amounts, etc.    │
   │ - Applies business rules        │
   │ - Updates invoice.extracted_data│
   │ - Status: parsing → completed   │
   └─────────────────────────────────┘
    ↓
4. Redirect to Show Page (invoice/:id)
   - User reviews extracted data
   - User can edit any field
   - User clicks "Save & Upload"
    ↓
5. Background Jobs (triggered after user confirms)
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

**Key Changes from Original Design:**
- ✅ Parsing is now SYNCHRONOUS (happens in controller, not background job)
- ✅ User can review and correct data before it goes to Google Drive/Sheets
- ✅ Better UX - immediate feedback, no waiting for background jobs
- ✅ Background jobs only run AFTER user confirms the data

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
  # Example structure:
  # {
  #   "date": "7-Feb-2025",
  #   "particulars": "Starbucks",
  #   "type": "debit",
  #   "classification": "office",
  #   "description": "meeting with client",
  #   "amount_inr": "500",
  #   "amount_usd": null,
  #   "mode_of_transaction": "rishi paid for it",
  #   "currency": "INR",
  #   "invoice_type": "restaurant",
  #   "total_amount": 500,
  #   "parsed_at": "2025-02-07 12:34:56 UTC"
  # }

  # Google Drive results
  t.string :google_drive_url
  t.string :google_drive_file_id

  # Google Sheets results
  t.integer :google_sheet_row_number
  t.string :google_sheet_url

  # Error tracking
  t.text :error_message
  t.datetime :processed_at

  t.timestamps
end
```

**Active Storage Attachment:**
- `invoice.image` - The uploaded invoice/receipt image (JPEG, PNG, HEIC, etc.)

**Notes:**
- ❌ `manual_date` field was removed (no longer needed)
- ✅ All data is extracted by AI, then user can edit on show page
- ✅ Business rules automatically set: type, mode_of_transaction, classification, description

---

## File Structure

```
app/
├── controllers/
│   └── invoices_controller.rb    # Handles upload, show, update actions
├── services/
│   └── invoice_parser.rb         # AI parsing service (synchronous)
├── jobs/
│   ├── drive_upload_job.rb       # Google Drive upload (IMPLEMENTED)
│   └── sheet_update_job.rb       # Google Sheets append (IMPLEMENTED)
├── models/
│   └── invoice.rb                # Invoice model with status enums
└── views/
    └── invoices/
        ├── new.html.erb          # Upload form
        ├── show.html.erb         # Review/edit extracted data
        └── thank_you.html.erb    # Legacy success page (not used)

config/
├── credentials.yml.enc           # Encrypted: anthropic_api_key, google_oauth
├── database.yml                  # PostgreSQL + Solid Queue config
├── storage.yml                   # Active Storage config
└── routes.rb                     # Root: invoices#new

db/
├── schema.rb                     # Main database schema
└── queue_schema.rb               # Solid Queue tables

deploy.sh                         # Deployment script for production
```

**Key Files:**

- **`app/services/invoice_parser.rb`** - Core AI parsing logic (replaces ImageParsingJob)
  - HEIC conversion, image compression
  - Claude API integration
  - Business rules application

- **`app/controllers/invoices_controller.rb`** - Main controller with:
  - `new` - Upload form
  - `create` - Saves invoice + runs parsing synchronously
  - `show` - Display extracted data with editable form
  - `update` - Save corrections + trigger background jobs

- **`app/views/invoices/show.html.erb`** - Review page with editable fields

- **`deploy.sh`** - Production deployment script

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

# Add:
anthropic_api_key: sk-ant-api03-YOUR-KEY-HERE
```

**2. Google OAuth Setup (Required):**

Create OAuth credentials in Google Cloud Console:
1. Go to Google Cloud Console → APIs & Services → Credentials
2. Create OAuth 2.0 Client ID (Application type: Web application)
3. Add redirect URI: `urn:ietf:wg:oauth:2.0:oob`
4. Enable Google Drive API and Google Sheets API

Run authorization locally:
```bash
bin/rails google:authorize
```

This will:
- Open browser for authorization
- Save refresh token to Rails credentials automatically

**3. Add Google IDs to credentials:**
```bash
EDITOR="nano" bin/rails credentials:edit

# Add full structure:
google_oauth:
  client_id: YOUR_CLIENT_ID.apps.googleusercontent.com
  client_secret: YOUR_CLIENT_SECRET
  project_id: YOUR_PROJECT_ID
  refresh_token: YOUR_REFRESH_TOKEN  # Auto-saved by google:authorize
google_drive_folder_id: YOUR_FOLDER_ID
google_sheet_id: YOUR_SHEET_ID
```

**4. Copy credentials to production:**

After running `bin/rails google:authorize` locally, copy the entire `google_oauth` section (including refresh_token) to production credentials:

```bash
# On production server
EDITOR="nano" bin/rails credentials:edit --environment production
# Paste the google_oauth section
```

**Important:** The refresh token works indefinitely, so you only need to authorize once locally and copy to production.

---

## API Integration Details

### Anthropic Claude API

**Current Model:** `claude-3-haiku-20240307`
- Fast and cost-effective (~$0.001-0.003 per invoice)
- Good accuracy for structured document parsing
- Supports vision (image input)

**Image Processing (InvoiceParser service):**
- Auto-converts HEIC to JPEG using ImageProcessing::MiniMagick
- Compresses images to 2000x2000 to prevent API timeouts
- Base64 encodes images for API transmission
- Accepts: JPEG, PNG, GIF, WebP, HEIC

**Prompt Strategy:**
- Extracts: particulars, date, total_amount, currency, invoice_type
- Focuses on INVOICE DATE (not expiry/order date)
- Returns JSON-only output (no explanation)
- Classifies invoice as: restaurant, travel, or other

**Business Rules (Applied Automatically):**
```ruby
# Fixed values
extracted_data["type"] = "debit"
extracted_data["mode_of_transaction"] = "rishi paid for it"

# Currency-based amount splitting
if currency == "INR"
  extracted_data["amount_inr"] = total_amount
  extracted_data["amount_usd"] = nil
elsif currency == "USD"
  extracted_data["amount_usd"] = total_amount
  extracted_data["amount_inr"] = nil

# Invoice type-based classification
if invoice_type == "restaurant"
  extracted_data["classification"] = "office"
  extracted_data["description"] = "meeting with client"
elsif invoice_type == "travel"
  extracted_data["classification"] = "travel"
  extracted_data["description"] = "travel for meeting"
else
  extracted_data["classification"] = "other"
  extracted_data["description"] = nil
```

**User-Editable Fields (on show page):**
- Date, Particulars, Type, Classification, Description
- Amount (INR), Amount (USD)
- Mode of Transaction (dropdown: "rishi paid for it", "rupali paid for it", "paid via company account")

**Error Handling:**
- Errors shown immediately to user (synchronous)
- Saves error messages to `invoice.error_message`
- Redirects back to upload form with error message

### Google Drive API ✅ IMPLEMENTED

**Implementation (DriveUploadJob):**
- Uses OAuth2 User Refresh Token (stored in Rails credentials)
- No `tmp/google_tokens.yaml` file needed
- Uploads to specific folder (configured in credentials)
- Filename format: `"YYYY-MM-DD - Vendor Name - Invoice ID.jpg"`
- Returns `web_view_link` for accessing file

**Authentication:**
```ruby
credentials = Google::Auth::UserRefreshCredentials.new(
  client_id: Rails.application.credentials.dig(:google_oauth, :client_id),
  client_secret: Rails.application.credentials.dig(:google_oauth, :client_secret),
  scope: ['https://www.googleapis.com/auth/drive.file'],
  refresh_token: Rails.application.credentials.dig(:google_oauth, :refresh_token)
)
```

### Google Sheets API ✅ IMPLEMENTED

**Implementation (SheetUpdateJob):**

**Column Structure (9 columns):**
1. Date (e.g., "7-Feb-2025")
2. Particulars (vendor name)
3. Type (always "debit")
4. Classification (office, travel, other)
5. Description
6. Amount (INR)
7. Amount (USD)
8. Mode of Transaction ("rishi paid for it", "rupali paid for it", "paid via company account")
9. Receipt URL (Google Drive link)

**Code:**
```ruby
# Uses same OAuth2 refresh token authentication as Drive
row = [
  data['date'],
  data['particulars'],
  data['type'],
  data['classification'],
  data['description'],
  data['amount_inr'],
  data['amount_usd'],
  data['mode_of_transaction'],
  invoice.google_drive_url
]

range = 'Sheet1!A:I'
value_range = Google::Apis::SheetsV4::ValueRange.new(values: [row])
result = service.append_spreadsheet_value(
  sheet_id,
  range,
  value_range,
  value_input_option: 'USER_ENTERED'
)
```

**Returns:**
- Row number where data was appended
- Direct URL to the row in Google Sheets

---

## Running Jobs

### Background Jobs (Only Drive & Sheets Upload)

**Important:** Parsing is NO LONGER a background job! It happens synchronously in the controller.

**Background jobs:**
- `DriveUploadJob` - Uploads to Google Drive
- `SheetUpdateJob` - Appends to Google Sheets

**Start Background Worker:**
```bash
bin/jobs  # Development
RAILS_ENV=production bin/jobs  # Production
```

**What it does:**
- Polls Solid Queue database for pending jobs
- Executes jobs in separate threads
- Auto-retries failed jobs (3 attempts)
- Logs to `log/production.log`

**Important:**
- Must restart after code changes (doesn't auto-reload like Rails server)
- Can run multiple workers for parallel processing
- Uses PostgreSQL for job queue (no Redis needed)

### Manual Job Execution (for testing)

```bash
# Run job synchronously (for debugging)
bin/rails runner "DriveUploadJob.perform_now(invoice_id)"
bin/rails runner "SheetUpdateJob.perform_now(invoice_id)"

# Check job status
bin/rails runner "
  SolidQueue::Job.where(class_name: 'DriveUploadJob').each do |job|
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

## Deployment

### Production Deployment Script

Use the included `deploy.sh` script for easy deployment:

```bash
# On production server
cd /path/to/invoicemanager
./deploy.sh
```

**What it does:**
1. Pulls latest code from main branch (`git pull origin main`)
2. Installs dependencies (`bundle install`)
3. Runs database migrations (`db:migrate`)
4. Restarts Puma and Solid Queue workers (`systemctl restart puma solid-queue`)

**Prerequisites:**
- Git repository set up on server
- Puma and Solid Queue configured as systemd services
- Sudo access for restarting services

**Force Push Recovery:**
If you force-pushed to main and get divergent branches error:
```bash
git fetch origin main
git reset --hard origin/main
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

### Google OAuth Authentication Errors

**Problem:** `invalid_grant` or "Token has been expired or revoked"

**Solutions:**
1. **Re-authorize locally:**
   ```bash
   rm tmp/google_tokens.yaml  # Delete old token
   bin/rails google:authorize  # Get new refresh token
   ```

2. **Copy refresh token to production:**
   ```bash
   # Get token from local credentials
   bin/rails runner "puts Rails.application.credentials.dig(:google_oauth, :refresh_token)"

   # On production, edit credentials and paste the token
   EDITOR="nano" bin/rails credentials:edit --environment production
   ```

3. **Check credentials structure:**
   ```yaml
   google_oauth:
     client_id: ...
     client_secret: ...
     refresh_token: ...  # Must be present!
   ```

**Problem:** Production can't authorize (no browser)

**Solution:** Always authorize locally and copy the entire `google_oauth` section to production credentials. Never try to run `bin/rails google:authorize` on production.

### Force Push Issues

**Problem:** `divergent branches` after force push

**Solution:**
```bash
git fetch origin main
git reset --hard origin/main
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
```yaml
anthropic_api_key: sk-ant-api03-...

google_oauth:
  client_id: XXX.apps.googleusercontent.com
  client_secret: GOCSPX-...
  project_id: invoicemanagement-XXX
  refresh_token: 1//0g...  # Never expires

google_drive_folder_id: 1ABC...
google_sheet_id: 1XYZ...
```

**Master key:** `config/master.key` (NOT in git, required to decrypt)

**Edit Credentials:**
```bash
# Development
EDITOR="nano" bin/rails credentials:edit

# Production
EDITOR="nano" bin/rails credentials:edit --environment production
```

**Authorization:**
- Run `bin/rails google:authorize` once locally
- Refresh token is saved to credentials automatically
- Copy entire `google_oauth` section to production credentials
- No need to authorize on production server (can't open browser there)

### .gitignore Protection

**Never commit:**
- `config/master.key` ⚠️
- `config/credentials/production.key` ⚠️
- `config/*.key` ⚠️
- `.env*` ⚠️
- `storage/*` (uploaded images)
- `tmp/*`
- `log/*`

**Safe to commit:**
- `config/credentials.yml.enc` ✅ (encrypted)
- `config/credentials/production.yml.enc` ✅ (encrypted)
- All code files (use `Rails.application.credentials`)

---

## Current Status

### ✅ Fully Implemented & Working
- Rails 8 app with PostgreSQL
- Active Storage for image uploads
- Solid Queue background jobs
- Invoice model with detailed status tracking
- **InvoiceParser service** - Synchronous AI parsing with Claude API
- HEIC to JPEG automatic conversion with compression
- **Review/Edit flow** - User can correct AI-extracted data before upload
- **Google Drive API** - Uploads images to Drive with OAuth2
- **Google Sheets API** - Appends data to Sheet with OAuth2
- Web UI with upload and review pages
- Status tracking per step
- Business rules for automatic classification
- Deployment script (`deploy.sh`)

### 📋 Optional Future Enhancements
1. User dashboard to view processed invoices
2. Retry/reprocess UI for failed invoices
3. Search and filter invoices
4. Bulk upload support
5. Export to CSV/Excel
6. User authentication (currently single-user system)
7. Multi-user support with permissions

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
