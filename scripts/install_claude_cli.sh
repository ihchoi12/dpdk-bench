#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}Claude CLI Installation Script${NC}"
echo -e "${GREEN}================================${NC}"
echo ""

# Function to print status
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    print_error "Please do not run this script as root"
    exit 1
fi

# Update package lists
print_status "Updating package lists..."
sudo apt update -qq

# Check and install curl
if ! command -v curl &> /dev/null; then
    print_status "Installing curl..."
    sudo apt install -y curl
else
    print_status "curl is already installed"
fi

# Check Node.js version
NODE_REQUIRED_VERSION=18
if command -v node &> /dev/null; then
    NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_VERSION" -ge "$NODE_REQUIRED_VERSION" ]; then
        print_status "Node.js v$(node -v) is already installed"
    else
        print_warning "Node.js version is too old ($(node -v)), upgrading..."
        INSTALL_NODE=1
    fi
else
    print_status "Node.js not found, installing..."
    INSTALL_NODE=1
fi

# Install Node.js if needed
if [ "$INSTALL_NODE" = "1" ]; then
    print_status "Installing Node.js v20 (LTS)..."

    # Remove old nodejs if exists
    sudo apt remove -y nodejs npm 2>/dev/null || true

    # Install NodeSource repository
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -

    # Install Node.js
    sudo apt install -y nodejs

    # Verify installation
    if command -v node &> /dev/null; then
        print_status "Node.js v$(node -v) installed successfully"
        print_status "npm v$(npm -v) installed successfully"
    else
        print_error "Node.js installation failed"
        exit 1
    fi
fi

# Check and install build-essential (sometimes needed for npm packages)
if ! dpkg -l | grep -q build-essential; then
    print_status "Installing build-essential..."
    sudo apt install -y build-essential
else
    print_status "build-essential is already installed"
fi

# Check if Claude CLI is already installed
if command -v claude &> /dev/null; then
    print_warning "Claude CLI is already installed (version: $(claude --version 2>/dev/null || echo 'unknown'))"
    read -p "Do you want to reinstall? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Skipping installation"
        exit 0
    fi
    print_status "Uninstalling existing Claude CLI..."
    sudo npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true
fi

# Install Claude CLI globally
print_status "Installing Claude CLI..."
if sudo npm install -g @anthropic-ai/claude-code; then
    print_status "Claude CLI installed successfully"
else
    print_error "Failed to install Claude CLI"
    print_warning "Trying alternative installation method..."

    # Try installing without sudo if it fails
    if npm install -g @anthropic-ai/claude-code; then
        print_status "Claude CLI installed successfully (user installation)"
    else
        print_error "Installation failed. Please check npm configuration"
        exit 1
    fi
fi

# Verify installation
if command -v claude &> /dev/null; then
    print_status "Claude CLI is now available: $(which claude)"
    CLAUDE_VERSION=$(claude --version 2>/dev/null || echo "version unknown")
    print_status "Version: $CLAUDE_VERSION"
else
    print_error "Claude CLI installation verification failed"
    print_warning "You may need to add npm global bin to your PATH"

    # Get npm global bin path
    NPM_BIN=$(npm bin -g 2>/dev/null || echo "")
    if [ -n "$NPM_BIN" ]; then
        print_warning "Try adding this to your ~/.bashrc or ~/.zshrc:"
        echo "    export PATH=\"$NPM_BIN:\$PATH\""
    fi
    exit 1
fi

# Check for API key
echo ""
print_status "Checking API key configuration..."

if [ -f "$HOME/.config/claude/config.json" ]; then
    print_status "Config file exists at ~/.config/claude/config.json"
    if grep -q "apiKey" "$HOME/.config/claude/config.json" 2>/dev/null; then
        print_status "API key is configured"
    else
        print_warning "Config file exists but no API key found"
        NEED_API_KEY=1
    fi
else
    print_warning "No config file found"
    NEED_API_KEY=1
fi

if [ "$NEED_API_KEY" = "1" ]; then
    echo ""
    echo -e "${YELLOW}================================${NC}"
    echo -e "${YELLOW}API Key Setup Required${NC}"
    echo -e "${YELLOW}================================${NC}"
    echo ""
    echo "To use Claude CLI, you need to set up your API key."
    echo ""
    echo "Option 1: Run 'claude auth login' to authenticate interactively"
    echo "Option 2: Set ANTHROPIC_API_KEY environment variable"
    echo "Option 3: Create config file at ~/.config/claude/config.json"
    echo ""

    read -p "Do you want to run 'claude auth login' now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        claude auth login
    else
        print_warning "Skipping API key setup. You'll need to configure it manually later."
    fi
fi

# Final verification
echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
print_status "Claude CLI is installed and ready to use"
echo ""
echo "Quick start:"
echo "  1. Authenticate: claude auth login"
echo "  2. Start a session: claude"
echo "  3. Chat with Claude in your terminal!"
echo ""
echo "For help: claude --help"
echo ""

# Test basic command
if claude --version &> /dev/null; then
    print_status "Installation verified successfully!"
    exit 0
else
    print_warning "Installation completed but verification failed"
    print_warning "You may need to restart your shell or source your profile"
    exit 0
fi
