#!/bin/bash
set -e

echo "=================================="
echo "Production Server Setup"
echo "=================================="

# Get configuration
read -p "Enter your domain name (e.g., invoicemanager.yourdomain.com): " DOMAIN
read -p "Enter your email for SSL certificate: " EMAIL
read -p "Enter app directory path (default: /root/projects/invoicemanagement): " APP_DIR
APP_DIR=${APP_DIR:-/root/projects/invoicemanagement}

echo ""
echo "Configuration:"
echo "  Domain: $DOMAIN"
echo "  Email: $EMAIL"
echo "  App Directory: $APP_DIR"
echo ""
read -p "Continue with these settings? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Install Nginx
echo ""
echo "Step 1: Installing Nginx..."
sudo apt-get update
sudo apt-get install -y nginx

# Install Certbot (Let's Encrypt)
echo ""
echo "Step 2: Installing Certbot for SSL..."
sudo apt-get install -y certbot python3-certbot-nginx

# Create Nginx configuration
echo ""
echo "Step 3: Creating Nginx configuration..."
sudo tee /etc/nginx/sites-available/invoicemanager > /dev/null <<EOF
upstream puma {
  server unix://$APP_DIR/tmp/sockets/puma.sock;
}

server {
  listen 80;
  listen [::]:80;
  server_name $DOMAIN;

  root $APP_DIR/public;

  # Redirect to HTTPS (will be enabled after SSL setup)
  # return 301 https://\$server_name\$request_uri;

  location / {
    proxy_pass http://puma;
    proxy_set_header Host \$http_host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_redirect off;
  }

  location ~ ^/(assets|packs)/ {
    gzip_static on;
    expires max;
    add_header Cache-Control public;
  }

  client_max_body_size 50M;
  keepalive_timeout 10;
}
EOF

# Enable site
sudo ln -sf /etc/nginx/sites-available/invoicemanager /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Test Nginx config
echo ""
echo "Testing Nginx configuration..."
sudo nginx -t

# Restart Nginx
echo ""
echo "Restarting Nginx..."
sudo systemctl restart nginx
sudo systemctl enable nginx

# Create Puma systemd service
echo ""
echo "Step 4: Creating Puma systemd service..."
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
echo "Step 5: Creating Solid Queue (jobs) systemd service..."
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

# Create necessary directories
echo ""
echo "Step 6: Creating necessary directories..."
mkdir -p $APP_DIR/tmp/sockets
mkdir -p $APP_DIR/tmp/pids
mkdir -p $APP_DIR/log

# Update Puma configuration
echo ""
echo "Step 7: Updating Puma configuration..."
cd $APP_DIR

cat > config/puma.rb <<'PUMA_EOF'
# Puma configuration for production

max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

port ENV.fetch("PORT") { 3000 }
environment ENV.fetch("RAILS_ENV") { "production" }

pidfile ENV.fetch("PIDFILE") { "tmp/pids/puma.pid" }

# Use socket for Nginx communication
bind "unix://#{Dir.pwd}/tmp/sockets/puma.sock"

workers ENV.fetch("WEB_CONCURRENCY") { 2 }
preload_app!

plugin :tmp_restart
PUMA_EOF

# Set up production environment
echo ""
echo "Step 8: Setting up production environment..."

# Generate SECRET_KEY_BASE if not in .env
if ! grep -q "SECRET_KEY_BASE=" .env 2>/dev/null; then
    echo "Generating SECRET_KEY_BASE..."
    SECRET_KEY=$(bundle exec rails secret)
    echo "SECRET_KEY_BASE=$SECRET_KEY" >> .env
fi

# Set RAILS_ENV
if ! grep -q "RAILS_ENV=production" .env 2>/dev/null; then
    echo "RAILS_ENV=production" >> .env
fi

# Install dependencies
echo ""
echo "Step 9: Installing dependencies..."
bundle install --deployment --without development test

# Set up database
echo ""
echo "Step 10: Setting up database..."
RAILS_ENV=production bundle exec rails db:create db:migrate

# Precompile assets
echo ""
echo "Step 11: Precompiling assets..."
RAILS_ENV=production bundle exec rails assets:precompile

# Set proper permissions
echo ""
echo "Step 12: Setting permissions..."
chmod -R 755 $APP_DIR
chmod 600 .env

# Reload systemd and start services
echo ""
echo "Step 13: Starting services..."
sudo systemctl daemon-reload
sudo systemctl enable puma solid-queue
sudo systemctl start puma
sudo systemctl start solid-queue

# Check service status
echo ""
echo "Checking service status..."
sleep 2
sudo systemctl status puma --no-pager
sudo systemctl status solid-queue --no-pager

# Set up SSL certificate
echo ""
echo "Step 14: Setting up SSL certificate..."
read -p "Set up SSL certificate now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL

    # Update Nginx to redirect HTTP to HTTPS
    sudo sed -i 's|# return 301|return 301|' /etc/nginx/sites-available/invoicemanager
    sudo nginx -t && sudo systemctl reload nginx

    echo "✅ SSL certificate installed!"
else
    echo "⚠️  Skipping SSL setup. Run this later:"
    echo "   sudo certbot --nginx -d $DOMAIN -m $EMAIL"
fi

echo ""
echo "=================================="
echo "✅ Production Setup Complete!"
echo "=================================="
echo ""
echo "Your app is now running at:"
echo "  http://$DOMAIN"
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
