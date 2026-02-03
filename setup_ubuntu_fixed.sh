#!/bin/bash
set -e  # Exit on error

echo "=================================="
echo "Ubuntu Server Setup - Fixed Version"
echo "=================================="

# Update system
echo ""
echo "Step 1: Updating system..."
sudo apt-get update
sudo apt-get upgrade -y

# Install dependencies
echo ""
echo "Step 2: Installing dependencies..."
sudo apt-get install -y \
  curl \
  gpg \
  gnupg2 \
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
  git \
  imagemagick \
  libmagickwand-dev

# Install PostgreSQL 16
echo ""
echo "Step 3: Installing PostgreSQL 16..."
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt-get update
sudo apt-get install -y postgresql-16 postgresql-contrib-16 libpq-dev
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Install Node.js
echo ""
echo "Step 4: Installing Node.js 20..."
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install RVM (more robust method)
echo ""
echo "Step 5: Installing RVM..."

# Import GPG keys
echo "Importing GPG keys..."
gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB || \
gpg --keyserver hkp://keys.openpgp.org --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB || \
gpg --keyserver hkp://pgp.mit.edu --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB

# Install RVM
echo "Downloading and installing RVM..."
\curl -sSL https://get.rvm.io | bash -s stable --ruby

# Wait a moment for RVM to complete installation
sleep 2

# Try to load RVM from different possible locations
echo ""
echo "Step 6: Loading RVM..."
if [ -s "$HOME/.rvm/scripts/rvm" ]; then
    source "$HOME/.rvm/scripts/rvm"
    echo "✅ RVM loaded from $HOME/.rvm/scripts/rvm"
elif [ -s "/usr/local/rvm/scripts/rvm" ]; then
    source "/usr/local/rvm/scripts/rvm"
    echo "✅ RVM loaded from /usr/local/rvm/scripts/rvm"
else
    echo "❌ ERROR: RVM installation not found!"
    echo "Checking RVM status..."
    which rvm || echo "RVM command not found"
    ls -la ~/.rvm/ 2>/dev/null || echo "~/.rvm directory doesn't exist"
    ls -la /usr/local/rvm/ 2>/dev/null || echo "/usr/local/rvm directory doesn't exist"
    exit 1
fi

# Verify RVM is working
echo ""
echo "Step 7: Verifying RVM..."
rvm --version || {
    echo "❌ ERROR: RVM command not working"
    exit 1
}

# Install Ruby 3.3.6
echo ""
echo "Step 8: Installing Ruby 3.3.6..."
rvm install 3.3.6
rvm use 3.3.6 --default

# Verify Ruby installation
echo ""
echo "Step 9: Verifying Ruby installation..."
ruby -v
gem -v

# Install bundler and rails
echo ""
echo "Step 10: Installing Bundler and Rails..."
gem install bundler
gem install rails -v '~> 8.0'

# Add RVM to bashrc if not already there
echo ""
echo "Step 11: Configuring shell..."
if [ -s "$HOME/.rvm/scripts/rvm" ]; then
    RVM_PATH="$HOME/.rvm/scripts/rvm"
elif [ -s "/usr/local/rvm/scripts/rvm" ]; then
    RVM_PATH="/usr/local/rvm/scripts/rvm"
fi

if ! grep -q "source $RVM_PATH" ~/.bashrc 2>/dev/null; then
    echo "" >> ~/.bashrc
    echo "# Load RVM into shell session" >> ~/.bashrc
    echo "[[ -s \"$RVM_PATH\" ]] && source \"$RVM_PATH\"" >> ~/.bashrc
    echo "Added RVM to ~/.bashrc"
fi

# Create PostgreSQL user (optional)
echo ""
echo "Step 12: PostgreSQL configuration..."
read -p "Create PostgreSQL user for app? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Enter username (default: deployer): " PG_USER
    PG_USER=${PG_USER:-deployer}
    sudo -u postgres psql -c "CREATE USER $PG_USER WITH PASSWORD 'changeme' CREATEDB;" 2>/dev/null || echo "User may already exist"
    echo "PostgreSQL user: $PG_USER (password: changeme)"
fi

echo ""
echo "=================================="
echo "✅ Installation Complete!"
echo "=================================="
echo ""
echo "Installed versions:"
echo "  - Ruby: $(ruby -v)"
echo "  - Bundler: $(bundle -v)"
echo "  - Rails: $(rails -v)"
echo "  - PostgreSQL: $(psql --version)"
echo "  - Node.js: $(node -v)"
echo ""
echo "⚠️  IMPORTANT: Reload your shell or logout/login"
echo ""
echo "To reload now:"
echo "  source ~/.bashrc"
echo ""
echo "Test it works:"
echo "  ruby -v"
echo "  rvm list"
echo ""
