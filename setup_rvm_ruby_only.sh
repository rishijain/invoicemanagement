#!/bin/bash
set -e  # Exit on error

echo "=================================="
echo "Installing RVM and Ruby 3.3.6 (minimal)"
echo "=================================="

# Update system
echo "Updating system..."
sudo apt-get update

# Install minimal dependencies for RVM and Ruby
echo "Installing dependencies..."
sudo apt-get install -y \
  curl \
  gpg \
  build-essential \
  libssl-dev \
  libreadline-dev \
  zlib1g-dev

# Add RVM GPG keys
echo "Adding RVM GPG keys..."
gpg --keyserver keyserver.ubuntu.com --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB

# Install RVM
echo "Installing RVM..."
curl -sSL https://get.rvm.io | bash -s stable

# Load RVM into current shell
echo "Loading RVM..."
source ~/.rvm/scripts/rvm

# Add RVM to shell profile
echo ""
echo "Adding RVM to ~/.bashrc..."
if ! grep -q "source ~/.rvm/scripts/rvm" ~/.bashrc; then
    echo "" >> ~/.bashrc
    echo "# Load RVM" >> ~/.bashrc
    echo "source ~/.rvm/scripts/rvm" >> ~/.bashrc
fi

# Install Ruby 3.3.6
echo "Installing Ruby 3.3.6 (this may take a few minutes)..."
rvm install 3.3.6

# Set as default
echo "Setting Ruby 3.3.6 as default..."
rvm use 3.3.6 --default

# Install bundler
echo "Installing Bundler..."
gem install bundler

echo ""
echo "=================================="
echo "✅ Installation Complete!"
echo "=================================="
echo ""
echo "Installed:"
echo "  - Ruby: $(ruby -v)"
echo "  - Gem: $(gem -v)"
echo "  - Bundler: $(bundle -v)"
echo ""
echo "⚠️  IMPORTANT: Reload your shell to use Ruby:"
echo "   source ~/.bashrc"
echo "   OR logout and login again"
echo ""
echo "Verify installation:"
echo "   ruby -v"
echo "   which ruby"
echo ""
