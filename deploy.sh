#!/bin/bash

# Invoice Manager Deployment Script
# Usage: ./deploy.sh

set -e  # Exit on error

echo "🚀 Starting deployment..."

# Pull latest code from main branch
echo "📥 Pulling latest code from main branch..."
git pull origin main

# Install/update dependencies
echo "📦 Installing dependencies..."
bundle install --without development test

# Run database migrations
echo "🗄️  Running database migrations..."
RAILS_ENV=production bin/rails db:migrate

# Restart Puma
sudo systemctl restart puma solid-queue
echo "🗄️  Restarted Puma and SolidQueue" 
