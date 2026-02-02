# Environment Configuration Guide

This app uses environment variables to configure Google Drive, Google Sheets, and Anthropic API settings. This allows you to use different values for development and production.

## Development Setup

1. **Copy the example file:**
   ```bash
   cp .env.example .env
   ```

2. **Edit `.env` with your development values:**
   ```bash
   nano .env
   ```

3. **Fill in your credentials:**
   ```env
   # Anthropic API
   ANTHROPIC_API_KEY=sk-ant-api03-YOUR-DEV-KEY

   # Google Drive Configuration (Development folder)
   GOOGLE_DRIVE_FOLDER_ID=your-dev-folder-id

   # Google Sheets Configuration (Development sheet)
   GOOGLE_SHEET_ID=your-dev-sheet-id

   # Google OAuth Credentials
   GOOGLE_OAUTH_CLIENT_ID=your-client-id.apps.googleusercontent.com
   GOOGLE_OAUTH_CLIENT_SECRET=your-client-secret
   ```

4. **Restart your Rails server and jobs:**
   ```bash
   # Terminal 1
   bin/rails server

   # Terminal 2
   bin/jobs
   ```

## Production Setup

### Option 1: Using .env file on server

1. Create `.env.production` on your production server:
   ```env
   ANTHROPIC_API_KEY=sk-ant-api03-YOUR-PROD-KEY
   GOOGLE_DRIVE_FOLDER_ID=your-prod-folder-id
   GOOGLE_SHEET_ID=your-prod-sheet-id
   GOOGLE_OAUTH_CLIENT_ID=your-client-id.apps.googleusercontent.com
   GOOGLE_OAUTH_CLIENT_SECRET=your-client-secret
   ```

2. Set `RAILS_ENV=production` when starting the app

### Option 2: Using system environment variables

Set these directly in your production environment:

```bash
export ANTHROPIC_API_KEY="sk-ant-api03-YOUR-PROD-KEY"
export GOOGLE_DRIVE_FOLDER_ID="your-prod-folder-id"
export GOOGLE_SHEET_ID="your-prod-sheet-id"
export GOOGLE_OAUTH_CLIENT_ID="your-client-id.apps.googleusercontent.com"
export GOOGLE_OAUTH_CLIENT_SECRET="your-client-secret"
```

### Option 3: Platform-specific (Heroku, Fly.io, etc.)

```bash
# Heroku example
heroku config:set ANTHROPIC_API_KEY=sk-ant-api03-YOUR-PROD-KEY
heroku config:set GOOGLE_DRIVE_FOLDER_ID=your-prod-folder-id
heroku config:set GOOGLE_SHEET_ID=your-prod-sheet-id
heroku config:set GOOGLE_OAUTH_CLIENT_ID=your-client-id.apps.googleusercontent.com
heroku config:set GOOGLE_OAUTH_CLIENT_SECRET=your-client-secret
```

### Option 4: Docker/Kamal

Add to your `.env` file in the deployment directory or pass via `-e` flags.

## Fallback to Rails Credentials

If environment variables are not set, the app will fall back to Rails encrypted credentials:

```bash
EDITOR="nano" bin/rails credentials:edit
```

Priority order:
1. Environment variables (`.env` file or system ENV)
2. Rails encrypted credentials (`config/credentials.yml.enc`)

## How to Get These Values

### Google Drive Folder ID
1. Create a folder in Google Drive
2. Open the folder
3. Copy the ID from the URL: `https://drive.google.com/drive/folders/ABC123...`
4. The folder ID is: `ABC123...`

### Google Sheet ID
1. Create a Google Sheet
2. Copy the ID from the URL: `https://docs.google.com/spreadsheets/d/XYZ789.../edit`
3. The sheet ID is: `XYZ789...`

### Google OAuth Credentials
1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create a project (or use existing)
3. Enable Google Drive API and Google Sheets API
4. Go to "APIs & Credentials" → "OAuth 2.0 Client IDs"
5. Create OAuth client ID (Desktop app)
6. Copy the Client ID and Client Secret

### Anthropic API Key
1. Go to [Anthropic Console](https://console.anthropic.com)
2. Create an API key
3. Copy the key (starts with `sk-ant-api03-`)

## Security Notes

- **Never commit `.env` to git** (already in `.gitignore`)
- `.env.example` is safe to commit (contains no secrets)
- Use different folders/sheets for dev/prod to avoid mixing data
- Rotate API keys regularly
- Use read-only access where possible

## Verification

Check if environment variables are loaded:

```bash
bin/rails runner "puts ENV['GOOGLE_DRIVE_FOLDER_ID']"
```

Should output your folder ID (not blank).
