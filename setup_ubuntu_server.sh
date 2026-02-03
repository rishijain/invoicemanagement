#!/bin/bash
set -e  # Exit on error

echo "=================================="
echo "Ubuntu Server Setup for Invoice Manager"
echo "Installing RVM, Ruby 3.3.6, and dependencies"
echo "=================================="

# Update system
echo ""
echo "Step 1: Updating system packages..."
sudo apt-get update
sudo apt-get upgrade -y

# Install essential dependencies
echo ""
echo "Step 2: Installing essential dependencies..."
sudo apt-get install -y \
  curl \
  gpg \
  build-essential \
  libssl-dev \
  libreadline-dev \
  zlib1g-dev \
  libsqlite3-dev \
  libpq-dev \
  libxml2-dev \
  libxslt1-dev \
  libcurl4-openssl-dev \
  software-properties-common \
  libffi-dev \
  libyaml-dev \
  git

# Install PostgreSQL 16
echo ""
echo "Step 3: Installing PostgreSQL 16..."
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt-get update
sudo apt-get install -y postgresql-16 postgresql-contrib-16 libpq-dev

# Start and enable PostgreSQL
sudo systemctl start postgresql
sudo systemctl enable postgresql

echo "PostgreSQL installed. You'll need to configure it later."

# Install ImageMagick (for HEIC conversion)
echo ""
echo "Step 4: Installing ImageMagick..."
sudo apt-get install -y imagemagick libmagickwand-dev

# Install Node.js (for Rails asset pipeline)
echo ""
echo "Step 5: Installing Node.js..."
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install RVM
echo ""
echo "Step 6: Installing RVM..."

# Add RVM GPG keys
gpg --keyserver keyserver.ubuntu.com --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB

# Install RVM
curl -sSL https://get.rvm.io | bash -s stable

# Load RVM
source ~/.rvm/scripts/rvm

# Install Ruby 3.3.6
echo ""
echo "Step 7: Installing Ruby 3.3.6..."
rvm install 3.3.6

# Set Ruby 3.3.6 as default
rvm use 3.3.6 --default

# Verify Ruby installation
echo ""
echo "Step 8: Verifying Ruby installation..."
ruby -v
gem -v

# Install bundler
echo ""
echo "Step 9: Installing Bundler..."
gem install bundler

# Install Rails
echo ""
echo "Step 10: Installing Rails..."
gem install rails -v '~> 8.0'

# Configure PostgreSQL (optional - creates a user)
echo ""
echo "Step 11: Configuring PostgreSQL..."
read -p "Create PostgreSQL user? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    read -p "Enter PostgreSQL username (default: deployer): " PG_USER
    PG_USER=${PG_USER:-deployer}

    sudo -u postgres psql -c "CREATE USER $PG_USER WITH PASSWORD 'changeme' CREATEDB;"
    echo "PostgreSQL user '$PG_USER' created with password 'changeme'"
    echo "⚠️  IMPORTANT: Change this password in production!"
fi

echo ""
echo "=================================="
echo "✅ Installation Complete!"
echo "=================================="
echo ""
echo "Installed:"
echo "  - RVM: $(rvm --version | head -n1)"
echo "  - Ruby: $(ruby -v)"
echo "  - Bundler: $(bundle -v)"
echo "  - Rails: $(rails -v)"
echo "  - PostgreSQL: $(psql --version)"
echo "  - Node.js: $(node -v)"
echo "  - ImageMagick: $(magick -version | head -n1)"
echo ""
echo "Next steps:"
echo "  1. Reload your shell: source ~/.bashrc (or logout and login)"
echo "  2. Clone your repository: git clone <repo-url>"
echo "  3. cd into project directory"
echo "  4. Copy .env.example to .env and configure"
echo "  5. Run: bundle install"
echo "  6. Configure database.yml for production"
echo "  7. Run: rails db:create db:migrate"
echo "  8. Start the app!"
echo ""
