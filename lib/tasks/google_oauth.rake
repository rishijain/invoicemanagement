require 'googleauth'
require 'googleauth/stores/file_token_store'

namespace :google do
  desc "Authorize Google Drive and Sheets OAuth access"
  task authorize: :environment do
    OOB_URI = 'urn:ietf:wg:oauth:2.0:oob'
    SCOPES = [
      'https://www.googleapis.com/auth/drive.file',
      'https://www.googleapis.com/auth/spreadsheets'
    ]

    client_id = Rails.application.credentials.google_oauth[:client_id]
    client_secret = Rails.application.credentials.google_oauth[:client_secret]

    authorizer = Google::Auth::UserAuthorizer.new(
      Google::Auth::ClientId.new(client_id, client_secret),
      SCOPES,
      Google::Auth::Stores::FileTokenStore.new(file: Rails.root.join('tmp', 'google_tokens.yaml'))
    )

    user_id = 'default'

    # Check if we already have credentials
    credentials = authorizer.get_credentials(user_id)

    if credentials.nil?
      puts "\n🔐 Google Drive OAuth Authorization"
      puts "=" * 60
      puts "\nOpening your browser for authorization..."
      puts "If the browser doesn't open, copy this URL:\n\n"

      url = authorizer.get_authorization_url(base_url: OOB_URI)
      puts url
      puts "\n" + "=" * 60

      # Try to open browser automatically
      system("open '#{url}'") if RUBY_PLATFORM =~ /darwin/
      system("xdg-open '#{url}'") if RUBY_PLATFORM =~ /linux/
      system("start '#{url}'") if RUBY_PLATFORM =~ /win32|mingw/

      puts "\nAfter authorizing, paste the authorization code here:"
      print "> "
      code = STDIN.gets.chomp

      credentials = authorizer.get_and_store_credentials_from_code(
        user_id: user_id,
        code: code,
        base_url: OOB_URI
      )

      puts "\n✅ Authorization successful!"
      puts "Tokens saved to: tmp/google_tokens.yaml"
      puts "\nNow updating Rails credentials with refresh token..."

      # Update credentials with refresh token
      update_credentials_with_token(credentials.refresh_token)

      puts "✅ Done! Google Drive is now configured."
    else
      puts "✅ Already authorized! Credentials found."
      puts "To re-authorize, delete tmp/google_tokens.yaml and run again."
    end
  end

  desc "Setup Google Sheet headers"
  task setup_sheet: :environment do
    require 'google/apis/sheets_v4'

    puts "\n📊 Setting up Google Sheet headers..."

    begin
      service = Google::Apis::SheetsV4::SheetsService.new
      service.authorization = get_google_credentials

      sheet_id = Rails.application.credentials.google_sheet_id

      # Prepare header row
      headers = [
        ['Date', 'Vendor', 'Invoice Number', 'Total Amount', 'Tax Amount', 'Currency', 'Drive Link', 'Processed At']
      ]

      range = 'Sheet1!A1:H1'
      value_range = Google::Apis::SheetsV4::ValueRange.new(values: headers)

      service.update_spreadsheet_value(
        sheet_id,
        range,
        value_range,
        value_input_option: 'RAW'
      )

      puts "✅ Headers added to Google Sheet!"
      puts "Columns: Date | Vendor | Invoice Number | Amount | Tax | Currency | Drive Link | Processed At"
      puts ""
      puts "View your sheet: https://docs.google.com/spreadsheets/d/#{sheet_id}"
    rescue => e
      puts "❌ Error: #{e.message}"
      puts "\nMake sure you:"
      puts "1. Enabled Google Sheets API"
      puts "2. Re-authorized with: bin/rails google:authorize"
    end
  end

  desc "Test Google Drive connection"
  task test: :environment do
    require 'google/apis/drive_v3'

    puts "\n🧪 Testing Google Drive connection..."

    begin
      service = Google::Apis::DriveV3::DriveService.new
      service.authorization = get_google_credentials

      # Test by listing files
      result = service.list_files(page_size: 1, fields: 'files(id, name)')

      puts "✅ Connection successful!"
      if result.files.any?
        puts "Sample file found: #{result.files.first.name}"
      end
    rescue => e
      puts "❌ Error: #{e.message}"
      puts "\nRun: bin/rails google:authorize"
    end
  end

  private

  def get_google_credentials
    client_id = Rails.application.credentials.google_oauth[:client_id]
    client_secret = Rails.application.credentials.google_oauth[:client_secret]
    refresh_token = Rails.application.credentials.google_oauth[:refresh_token]

    if refresh_token.nil?
      raise "No refresh token found. Run: bin/rails google:authorize"
    end

    authorizer = Google::Auth::UserAuthorizer.new(
      Google::Auth::ClientId.new(client_id, client_secret),
      [
        'https://www.googleapis.com/auth/drive.file',
        'https://www.googleapis.com/auth/spreadsheets'
      ],
      Google::Auth::Stores::FileTokenStore.new(file: Rails.root.join('tmp', 'google_tokens.yaml'))
    )

    authorizer.get_credentials('default')
  end

  def update_credentials_with_token(refresh_token)
    content = <<~YAML
      secret_key_base: #{Rails.application.credentials.secret_key_base}
      anthropic_api_key: #{Rails.application.credentials.anthropic_api_key}
      google_oauth:
        client_id: #{Rails.application.credentials.google_oauth[:client_id]}
        client_secret: #{Rails.application.credentials.google_oauth[:client_secret]}
        project_id: #{Rails.application.credentials.google_oauth[:project_id]}
        refresh_token: #{refresh_token}
    YAML

    File.write('/tmp/creds_with_token.yml', content)
    system("cat /tmp/creds_with_token.yml | EDITOR='tee' bin/rails credentials:edit > /dev/null 2>&1")
    File.delete('/tmp/creds_with_token.yml')
  end
end
