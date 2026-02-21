require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'webrick'

namespace :google do
  desc "Authorize Google Drive and Sheets OAuth access"
  task authorize: :environment do
    REDIRECT_URI = 'http://localhost:8080'
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

    puts "\n🔐 Google Drive OAuth Authorization"
    puts "=" * 60

    url = authorizer.get_authorization_url(base_url: REDIRECT_URI)

    puts "\nOpening browser for authorization..."
    puts "If it doesn't open automatically, visit:\n\n#{url}\n\n"

    system("open '#{url}'") if RUBY_PLATFORM =~ /darwin/
    system("xdg-open '#{url}'") if RUBY_PLATFORM =~ /linux/

    # Start a local server to capture the OAuth callback
    code = nil
    server = WEBrick::HTTPServer.new(
      Port: 8080,
      Logger: WEBrick::Log.new(File::NULL),
      AccessLog: []
    )

    server.mount_proc '/' do |req, res|
      code = req.query['code']
      res.body = '<html><body><h1>✅ Authorization successful!</h1><p>You can close this tab and return to the terminal.</p></body></html>'
      res.content_type = 'text/html'
      server.shutdown
    end

    puts "Waiting for authorization in browser..."
    server.start

    if code.nil?
      puts "❌ No authorization code received."
      exit 1
    end

    credentials = authorizer.get_and_store_credentials_from_code(
      user_id: user_id,
      code: code,
      base_url: REDIRECT_URI
    )

    puts "\n✅ Authorization successful!"
    puts "Updating Rails credentials with refresh token..."

    update_credentials_with_token(credentials.refresh_token)

    puts "✅ Done! Google Drive and Sheets are now configured."
  end

  desc "Setup Google Sheet headers"
  task setup_sheet: :environment do
    require 'google/apis/sheets_v4'

    puts "\n📊 Setting up Google Sheet headers..."

    begin
      service = Google::Apis::SheetsV4::SheetsService.new
      service.authorization = get_google_credentials

      sheet_id = Rails.application.credentials.google_sheet_id

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
    rescue => e
      puts "❌ Error: #{e.message}"
      puts "\nMake sure you have run: bin/rails google:authorize"
    end
  end

  desc "Test Google Drive connection"
  task test: :environment do
    require 'google/apis/drive_v3'

    puts "\n🧪 Testing Google Drive connection..."

    begin
      service = Google::Apis::DriveV3::DriveService.new
      service.authorization = get_google_credentials

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
      google_drive_folder_id: #{Rails.application.credentials.google_drive_folder_id}
      google_sheet_id: #{Rails.application.credentials.google_sheet_id}
    YAML

    File.write('/tmp/creds_with_token.yml', content)
    system("cat /tmp/creds_with_token.yml | EDITOR='tee' bin/rails credentials:edit > /dev/null 2>&1")
    File.delete('/tmp/creds_with_token.yml')
  end
end
