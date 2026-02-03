# Production Deployment Guide

## Prerequisites

- Ubuntu server with root access
- Domain name pointed to server IP
- Ruby 3.3.6 installed (via RVM)
- PostgreSQL 16 installed
- Git repository cloned

## Automated Setup

Run the automated setup script:

```bash
cd ~/projects/invoicemanagement
bash setup_production_server.sh
```

The script will:
1. Install and configure Nginx
2. Install Certbot (Let's Encrypt SSL)
3. Create systemd services for Puma and Solid Queue
4. Configure Puma for production
5. Set up SSL certificate
6. Start all services

## Manual Setup (If Script Fails)

### 1. Install Nginx

```bash
sudo apt-get update
sudo apt-get install -y nginx
```

### 2. Configure Environment

```bash
cd ~/projects/invoicemanagement

# Generate secret key
echo "SECRET_KEY_BASE=$(bundle exec rails secret)" >> .env
echo "RAILS_ENV=production" >> .env

# Edit .env with production values
nano .env
```

### 3. Install Dependencies

```bash
bundle install --deployment --without development test
```

### 4. Database Setup

```bash
RAILS_ENV=production rails db:create
RAILS_ENV=production rails db:migrate
```

### 5. Precompile Assets

```bash
RAILS_ENV=production rails assets:precompile
```

### 6. Create Puma Configuration

Create `config/puma.rb`:

```ruby
max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

port ENV.fetch("PORT") { 3000 }
environment ENV.fetch("RAILS_ENV") { "production" }

pidfile ENV.fetch("PIDFILE") { "tmp/pids/puma.pid" }
bind "unix://#{Dir.pwd}/tmp/sockets/puma.sock"

workers ENV.fetch("WEB_CONCURRENCY") { 2 }
preload_app!

plugin :tmp_restart
```

### 7. Create Systemd Service for Puma

Create `/etc/systemd/system/puma.service`:

```ini
[Unit]
Description=Puma HTTP Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/projects/invoicemanagement
Environment=RAILS_ENV=production

ExecStart=/usr/local/rvm/wrappers/ruby-3.3.6/bundle exec puma -C config/puma.rb
Restart=always

StandardOutput=append:/var/log/puma.log
StandardError=append:/var/log/puma_error.log

[Install]
WantedBy=multi-user.target
```

### 8. Create Systemd Service for Solid Queue

Create `/etc/systemd/system/solid-queue.service`:

```ini
[Unit]
Description=Solid Queue Background Jobs
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/projects/invoicemanagement
Environment=RAILS_ENV=production

ExecStart=/usr/local/rvm/wrappers/ruby-3.3.6/bundle exec rails solid_queue:start
Restart=always

StandardOutput=append:/var/log/solid_queue.log
StandardError=append:/var/log/solid_queue_error.log

[Install]
WantedBy=multi-user.target
```

### 9. Create Nginx Configuration

Create `/etc/nginx/sites-available/invoicemanager`:

```nginx
upstream puma {
  server unix:///root/projects/invoicemanagement/tmp/sockets/puma.sock;
}

server {
  listen 80;
  server_name yourdomain.com;

  root /root/projects/invoicemanagement/public;

  location / {
    proxy_pass http://puma;
    proxy_set_header Host $http_host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }

  location ~ ^/(assets|packs)/ {
    gzip_static on;
    expires max;
    add_header Cache-Control public;
  }

  client_max_body_size 50M;
}
```

### 10. Enable Services

```bash
# Create directories
mkdir -p tmp/sockets tmp/pids

# Enable Nginx site
sudo ln -s /etc/nginx/sites-available/invoicemanager /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Test and restart Nginx
sudo nginx -t
sudo systemctl restart nginx

# Enable and start services
sudo systemctl daemon-reload
sudo systemctl enable puma solid-queue
sudo systemctl start puma solid-queue

# Check status
sudo systemctl status puma
sudo systemctl status solid-queue
```

### 11. Set Up SSL (Let's Encrypt)

```bash
# Install Certbot
sudo apt-get install -y certbot python3-certbot-nginx

# Get certificate
sudo certbot --nginx -d yourdomain.com -m your@email.com --agree-tos

# Auto-renewal is set up automatically
sudo certbot renew --dry-run
```

## Post-Deployment

### Check Services

```bash
# Check if services are running
sudo systemctl status puma
sudo systemctl status solid-queue
sudo systemctl status nginx

# View logs
sudo journalctl -u puma -f
sudo journalctl -u solid-queue -f
tail -f log/production.log
```

### Test the Application

1. Visit: `https://yourdomain.com`
2. Upload a test invoice
3. Check logs to verify processing

### Firewall Configuration

```bash
# Allow HTTP and HTTPS
sudo ufw allow 80
sudo ufw allow 443

# Enable firewall
sudo ufw enable
```

## Updating the Application

When you push new code:

```bash
cd ~/projects/invoicemanagement

# Pull latest code
git pull origin main

# Install new dependencies (if any)
bundle install

# Run migrations (if any)
RAILS_ENV=production rails db:migrate

# Precompile assets (if changed)
RAILS_ENV=production rails assets:precompile

# Restart services
sudo systemctl restart puma
sudo systemctl restart solid-queue

# Check status
sudo systemctl status puma
sudo systemctl status solid-queue
```

## Troubleshooting

### Puma Won't Start

```bash
# Check logs
sudo journalctl -u puma -n 50
cat /var/log/puma_error.log

# Check if socket file exists
ls -la tmp/sockets/

# Try starting manually
RAILS_ENV=production bundle exec puma -C config/puma.rb
```

### 502 Bad Gateway

- Check if Puma is running: `sudo systemctl status puma`
- Check socket path in Nginx config matches Puma config
- Check Nginx error log: `sudo tail -f /var/log/nginx/error.log`

### Database Connection Issues

```bash
# Test database connection
RAILS_ENV=production rails runner "puts ActiveRecord::Base.connection.execute('SELECT 1').first"

# Check .env file has correct DATABASE_URL or credentials
cat .env | grep -E "DATABASE|DB_"
```

### Jobs Not Processing

```bash
# Check Solid Queue status
sudo systemctl status solid-queue
sudo journalctl -u solid-queue -f

# Check database for jobs
RAILS_ENV=production rails runner "puts SolidQueue::Job.count"
```

## Useful Commands

```bash
# Restart all services
sudo systemctl restart puma solid-queue nginx

# View all logs
sudo journalctl -u puma -u solid-queue -f

# Check service status
sudo systemctl status puma solid-queue nginx

# Reload Nginx (after config changes)
sudo nginx -t && sudo systemctl reload nginx

# Rails console in production
RAILS_ENV=production rails console

# Check disk space
df -h

# Check memory usage
free -h

# Check running processes
ps aux | grep -E "puma|solid_queue"
```

## Monitoring

### Set Up Log Rotation

Create `/etc/logrotate.d/invoicemanager`:

```
/var/log/puma.log
/var/log/solid_queue.log
/root/projects/invoicemanagement/log/production.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    copytruncate
}
```

### Monitor Disk Space

```bash
# Check disk usage
df -h

# Find large files
du -h --max-depth=1 /root/projects/invoicemanagement | sort -hr
```

## Security Checklist

- [ ] SSL certificate installed and auto-renewing
- [ ] Firewall enabled (only ports 80, 443, 22 open)
- [ ] `.env` file has restricted permissions (600)
- [ ] Database has strong password
- [ ] Regular backups configured
- [ ] Server OS regularly updated
- [ ] Application dependencies kept up to date

## Backup Strategy

```bash
# Backup database
pg_dump -U deployer invoicemanager_production > backup_$(date +%Y%m%d).sql

# Backup .env file
cp .env .env.backup

# Backup uploads (if using local storage)
tar -czf uploads_backup_$(date +%Y%m%d).tar.gz storage/
```

## Performance Tuning

### Increase Puma Workers

Edit `.env`:
```
WEB_CONCURRENCY=4
RAILS_MAX_THREADS=5
```

Then restart: `sudo systemctl restart puma`

### Database Connection Pool

Edit `config/database.yml`:
```yaml
production:
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
```

## Support

- Check logs first: `/var/log/puma.log`, `/var/log/solid_queue.log`
- Rails logs: `log/production.log`
- Nginx logs: `/var/log/nginx/error.log`
