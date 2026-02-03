#!/bin/bash
set -e

echo "=================================="
echo "Production Setup (IP Address Only)"
echo "=================================="

read -p "Enter app directory path (default: /root/projects/invoicemanagement): " APP_DIR
APP_DIR=${APP_DIR:-/root/projects/invoicemanagement}

echo ""
echo "Configuration:"
echo "  App Directory: $APP_DIR"
echo "  Access via: http://YOUR_SERVER_IP"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

cd $APP_DIR

# Set up production environment
echo ""
echo "Step 1: Setting up production environment..."

# Generate SECRET_KEY_BASE if not in .env
if ! grep -q "SECRET_KEY_BASE=" .env 2>/dev/null || grep -q "SECRET_KEY_BASE=generate" .env 2>/dev/null; then
    echo "Generating SECRET_KEY_BASE..."
    SECRET_KEY=$(bundle exec rails secret)

    if grep -q "SECRET_KEY_BASE=" .env 2>/dev/null; then
        sed -i "s|SECRET_KEY_BASE=.*|SECRET_KEY_BASE=$SECRET_KEY|" .env
    else
        echo "SECRET_KEY_BASE=$SECRET_KEY" >> .env
    fi
    echo "✅ SECRET_KEY_BASE generated"
else
    echo "✅ SECRET_KEY_BASE already set"
fi

# Set RAILS_ENV
if ! grep -q "RAILS_ENV=production" .env 2>/dev/null; then
    echo "RAILS_ENV=production" >> .env
    echo "✅ RAILS_ENV set to production"
fi

# Install dependencies
echo ""
echo "Step 2: Installing dependencies..."
bundle install --deployment --without development test

# Create necessary directories
echo ""
echo "Step 3: Creating directories..."
mkdir -p tmp/pids tmp/sockets log

# Set up PostgreSQL user
echo ""
echo "Step 4: Setting up PostgreSQL user..."
if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='root'" | grep -q 1; then
    echo "✅ PostgreSQL user 'root' already exists"
else
    echo "Creating PostgreSQL user 'root'..."
    sudo -u postgres createuser -s root
    echo "✅ PostgreSQL user 'root' created"
fi

# Set up database
echo ""
echo "Step 5: Setting up database..."
RAILS_ENV=production bundle exec rails db:create
RAILS_ENV=production bundle exec rails db:migrate

# Precompile assets
echo ""
echo "Step 6: Precompiling assets..."
# RAILS_ENV=production bundle exec rails assets:precompile

# Update Puma configuration for production
echo ""
echo "Step 7: Configuring Puma..."
cat > config/puma.rb <<'PUMA_EOF'
# Puma configuration for production

max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

# Bind to all interfaces on port 3000
port ENV.fetch("PORT") { 3000 }
bind "tcp://0.0.0.0:3000"

environment ENV.fetch("RAILS_ENV") { "production" }

pidfile ENV.fetch("PIDFILE") { "tmp/pids/puma.pid" }

workers ENV.fetch("WEB_CONCURRENCY") { 2 }
preload_app!

plugin :tmp_restart
PUMA_EOF

# Create Puma systemd service
echo ""
echo "Step 8: Creating Puma systemd service..."
sudo tee /etc/systemd/system/puma.service > /dev/null <<EOF
[Unit]
Description=Puma HTTP Server for Invoice Manager
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$APP_DIR
Environment=RAILS_ENV=production
Environment=RAILS_LOG_TO_STDOUT=true

ExecStart=/usr/local/rvm/wrappers/ruby-3.3.6/bundle exec puma -C config/puma.rb
ExecReload=/bin/kill -SIGUSR2 \$MAINPID

Restart=always
RestartSec=10

StandardOutput=append:/var/log/puma.log
StandardError=append:/var/log/puma_error.log

[Install]
WantedBy=multi-user.target
EOF

# Create Solid Queue systemd service
echo ""
echo "Step 9: Creating Solid Queue systemd service..."
sudo tee /etc/systemd/system/solid-queue.service > /dev/null <<EOF
[Unit]
Description=Solid Queue Background Jobs for Invoice Manager
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$APP_DIR
Environment=RAILS_ENV=production
Environment=RAILS_LOG_TO_STDOUT=true

ExecStart=/usr/local/rvm/wrappers/ruby-3.3.6/bundle exec rails solid_queue:start

Restart=always
RestartSec=10

StandardOutput=append:/var/log/solid_queue.log
StandardError=append:/var/log/solid_queue_error.log

[Install]
WantedBy=multi-user.target
EOF

# Set proper permissions
echo ""
echo "Step 10: Setting permissions..."
chmod 600 .env

# Enable and start services
echo ""
echo "Step 11: Starting services..."
sudo systemctl daemon-reload
sudo systemctl enable puma solid-queue
sudo systemctl start puma
sudo systemctl start solid-queue

# Wait a moment for services to start
sleep 3

# Check service status
echo ""
echo "Checking service status..."
sudo systemctl status puma --no-pager | head -20
echo ""
sudo systemctl status solid-queue --no-pager | head -20

# Open firewall port
echo ""
echo "Step 12: Opening firewall port..."
sudo ufw allow 3000 2>/dev/null || echo "Note: ufw not active or not installed"

# Get server IP
SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')

echo ""
echo "=================================="
echo "✅ Production Setup Complete!"
echo "=================================="
echo ""
echo "Your app is now running at:"
echo "  http://$SERVER_IP:3000"
echo ""
echo "Services:"
echo "  ✓ Puma (Rails app) - Port 3000"
echo "  ✓ Solid Queue (Background jobs)"
echo ""
echo "Useful commands:"
echo "  sudo systemctl status puma       # Check Rails status"
echo "  sudo systemctl status solid-queue  # Check jobs status"
echo "  sudo systemctl restart puma      # Restart Rails"
echo "  sudo systemctl restart solid-queue # Restart jobs"
echo "  sudo journalctl -u puma -f       # View Rails logs"
echo "  sudo journalctl -u solid-queue -f  # View jobs logs"
echo ""
echo "Log files:"
echo "  /var/log/puma.log"
echo "  /var/log/solid_queue.log"
echo "  $APP_DIR/log/production.log"
echo ""
echo "⚠️  Note: Access via http://$SERVER_IP:3000 (no SSL)"
echo ""
