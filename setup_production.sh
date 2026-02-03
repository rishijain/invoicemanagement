#!/bin/bash
set -e

echo "=================================="
echo "Production Environment Setup"
echo "=================================="

cd "$(dirname "$0")"

# Check if .env exists
if [ ! -f .env ]; then
    echo "Creating .env file from template..."
    cp .env.example .env
    echo "✅ .env file created"
else
    echo "✅ .env file already exists"
fi

# Generate secret key base if not set
echo ""
echo "Checking SECRET_KEY_BASE..."
if grep -q "SECRET_KEY_BASE=generate-with-rails-secret-command" .env || ! grep -q "SECRET_KEY_BASE=" .env; then
    echo "Generating new SECRET_KEY_BASE..."
    SECRET_KEY=$(bundle exec rails secret)

    # Replace or add SECRET_KEY_BASE
    if grep -q "SECRET_KEY_BASE=" .env; then
        sed -i "s|SECRET_KEY_BASE=.*|SECRET_KEY_BASE=$SECRET_KEY|" .env
    else
        echo "SECRET_KEY_BASE=$SECRET_KEY" >> .env
    fi
    echo "✅ SECRET_KEY_BASE generated"
else
    echo "✅ SECRET_KEY_BASE already set"
fi

# Configure database
echo ""
echo "Database Configuration"
echo "======================"
read -p "Configure database now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Database username (default: deployer): " DB_USER
    DB_USER=${DB_USER:-deployer}

    read -sp "Database password: " DB_PASS
    echo

    read -p "Database name (default: invoicemanager_production): " DB_NAME
    DB_NAME=${DB_NAME:-invoicemanager_production}

    read -p "Database host (default: localhost): " DB_HOST
    DB_HOST=${DB_HOST:-localhost}

    # Update .env with database config
    DATABASE_URL="postgresql://${DB_USER}:${DB_PASS}@${DB_HOST}/${DB_NAME}"

    if grep -q "DATABASE_URL=" .env; then
        sed -i "s|DATABASE_URL=.*|DATABASE_URL=$DATABASE_URL|" .env
    else
        echo "DATABASE_URL=$DATABASE_URL" >> .env
    fi

    echo "✅ Database configured"
fi

# Set RAILS_ENV
if ! grep -q "RAILS_ENV=production" .env; then
    echo "RAILS_ENV=production" >> .env
fi

echo ""
echo "=================================="
echo "Current .env Configuration:"
echo "=================================="
grep -v "PASSWORD\|SECRET\|API_KEY" .env || echo "(No non-sensitive vars to show)"

echo ""
echo "=================================="
echo "Next Steps:"
echo "=================================="
echo ""
echo "1. Edit .env and add your API keys and credentials:"
echo "   nano .env"
echo ""
echo "2. Install dependencies:"
echo "   bundle install"
echo ""
echo "3. Create database:"
echo "   RAILS_ENV=production rails db:create"
echo ""
echo "4. Run migrations:"
echo "   RAILS_ENV=production rails db:migrate"
echo ""
echo "5. Precompile assets:"
echo "   RAILS_ENV=production rails assets:precompile"
echo ""
echo "6. Start the server:"
echo "   RAILS_ENV=production rails server"
echo ""
echo "Or use this one-liner to set up everything:"
echo "  bundle install && RAILS_ENV=production rails db:create db:migrate assets:precompile"
echo ""
