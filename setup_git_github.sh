#!/bin/bash
set -e

echo "=================================="
echo "Git & GitHub Setup for Ubuntu Server"
echo "=================================="

# Install Git
echo ""
echo "Step 1: Installing Git..."
sudo apt-get update
sudo apt-get install -y git

# Verify Git installation
echo ""
echo "✅ Git installed: $(git --version)"

# Configure Git
echo ""
echo "Step 2: Configuring Git..."
read -p "Enter your name (for Git commits): " GIT_NAME
read -p "Enter your email (same as GitHub account): " GIT_EMAIL

git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"

echo "✅ Git configured:"
echo "   Name: $(git config --global user.name)"
echo "   Email: $(git config --global user.email)"

# Generate SSH key
echo ""
echo "Step 3: Generating SSH key for GitHub..."
SSH_KEY_PATH="$HOME/.ssh/id_ed25519"

if [ -f "$SSH_KEY_PATH" ]; then
    echo "⚠️  SSH key already exists at $SSH_KEY_PATH"
    read -p "Generate new key anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Using existing key."
    else
        ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$SSH_KEY_PATH" -N ""
        echo "✅ New SSH key generated"
    fi
else
    ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$SSH_KEY_PATH" -N ""
    echo "✅ SSH key generated"
fi

# Start SSH agent and add key
echo ""
echo "Step 4: Adding SSH key to agent..."
eval "$(ssh-agent -s)"
ssh-add "$SSH_KEY_PATH"

# Display public key
echo ""
echo "=================================="
echo "Step 5: Add this SSH key to GitHub"
echo "=================================="
echo ""
echo "Your public SSH key:"
echo "-------------------"
cat "${SSH_KEY_PATH}.pub"
echo "-------------------"
echo ""
echo "📋 Copy the key above and add it to GitHub:"
echo ""
echo "1. Go to: https://github.com/settings/keys"
echo "2. Click 'New SSH key'"
echo "3. Title: 'Ubuntu Production Server' (or whatever you want)"
echo "4. Paste the key above"
echo "5. Click 'Add SSH key'"
echo ""
read -p "Press Enter after you've added the key to GitHub..."

# Test GitHub connection
echo ""
echo "Step 6: Testing GitHub connection..."
ssh -T git@github.com 2>&1 | grep -q "successfully authenticated" && {
    echo "✅ GitHub connection successful!"
} || {
    echo "Testing connection..."
    ssh -T git@github.com
}

# Configure SSH to use key automatically
echo ""
echo "Step 7: Configuring SSH..."
mkdir -p ~/.ssh
chmod 700 ~/.ssh

cat > ~/.ssh/config <<EOF
Host github.com
    HostName github.com
    User git
    IdentityFile $SSH_KEY_PATH
    IdentitiesOnly yes
EOF

chmod 600 ~/.ssh/config
echo "✅ SSH config created"

echo ""
echo "=================================="
echo "✅ Git & GitHub Setup Complete!"
echo "=================================="
echo ""
echo "You can now clone your repository:"
echo "  git clone git@github.com:YOUR_USERNAME/YOUR_REPO.git"
echo ""
echo "Or if you already have the repo URL:"
echo "  git clone git@github.com:username/invoicemanager.git"
echo ""
