#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEOHOST_DIR="$SCRIPT_DIR"

# URLs for Mellanox public repository
SDK_URL="https://linux.mellanox.com/public/repo/mlnx_ofed/5.8-6.0.4.2/ubuntu22.04/amd64/neohost-sdk_1.5.0-102_amd64.deb"
BACKEND_URL="https://linux.mellanox.com/public/repo/mlnx_ofed/5.8-6.0.4.2/ubuntu22.04/amd64/neohost-backend_1.5.0-102_amd64.deb"
MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"

echo "========================================="
echo "NeoHost SDK Setup"
echo "========================================="
echo "Installing to: $NEOHOST_DIR"
echo ""

# Create temporary directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

cd "$TEMP_DIR"

# Download packages
echo "[1/6] Downloading NeoHost SDK..."
wget -q --show-progress "$SDK_URL" -O neohost-sdk.deb

echo "[2/6] Downloading NeoHost Backend..."
wget -q --show-progress "$BACKEND_URL" -O neohost-backend.deb

# Extract SDK (preserve full /opt/neohost/sdk structure)
echo "[3/6] Extracting SDK..."
dpkg-deb -x neohost-sdk.deb sdk_extracted
mkdir -p "$NEOHOST_DIR/sdk"
cp -r sdk_extracted/* "$NEOHOST_DIR/sdk/"

# Extract Backend (preserve full /opt/neohost/backend structure)
echo "[4/6] Extracting Backend..."
dpkg-deb -x neohost-backend.deb backend_extracted
mkdir -p "$NEOHOST_DIR/backend"
cp -r backend_extracted/* "$NEOHOST_DIR/backend/"

# Configure paths after extraction (before Miniconda installation)
echo "Configuring paths..."

# Update NEOHOST_COMMAND in SDK to use absolute path to backend
sed -i 's|NEOHOST_COMMAND = "neohost"|NEOHOST_COMMAND = "'"$NEOHOST_DIR"'/backend/opt/neohost/backend/neohost.sh"|' \
    "$NEOHOST_DIR/sdk/opt/neohost/sdk/neohost_sdk_constants.py"

# Install Miniconda with Python 2.7
if [ ! -d "$NEOHOST_DIR/miniconda3" ]; then
    echo "[5/6] Installing Miniconda (Python 2.7)..."
    wget -q --show-progress "$MINICONDA_URL" -O miniconda.sh

    # Temporarily disable strict error checking for Miniconda installer
    # (it may fail to cleanup temp dirs on NFS, but installation succeeds)
    set +e
    bash miniconda.sh -b -p "$NEOHOST_DIR/miniconda3"
    set -e

    # Verify Miniconda was installed
    if [ ! -f "$NEOHOST_DIR/miniconda3/bin/conda" ]; then
        echo "ERROR: Miniconda installation failed"
        exit 1
    fi

    # Accept Anaconda ToS
    echo "Accepting Anaconda Terms of Service..."
    "$NEOHOST_DIR/miniconda3/bin/conda" config --set channel_priority flexible
    "$NEOHOST_DIR/miniconda3/bin/conda" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main 2>/dev/null || true
    "$NEOHOST_DIR/miniconda3/bin/conda" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r 2>/dev/null || true

    # Create Python 2.7 environment
    echo "Creating Python 2.7 environment..."
    "$NEOHOST_DIR/miniconda3/bin/conda" create -n py27 -y python=2.7

    # Install dependencies
    echo "Installing Python dependencies..."
    "$NEOHOST_DIR/miniconda3/envs/py27/bin/pip" install --quiet \
        attrs==21.4.0 \
        certifi==2020.6.20 \
        configparser==4.0.2 \
        contextlib2==0.6.0.post1 \
        functools32==3.2.3.post2 \
        importlib-metadata==2.1.3 \
        jsonschema==3.2.0 \
        pathlib2==2.3.7.post1 \
        pyrsistent==0.16.1 \
        scandir==1.10.0 \
        six==1.17.0 \
        typing==3.10.0.0 \
        zipp==1.2.0
else
    echo "[5/6] Miniconda already installed, skipping..."
fi

# Update backend neohost.sh to use local Python and setup LD_LIBRARY_PATH
echo "Configuring backend to use local Python..."
# Set PY_EXEC to local Python
sed -i '9s|.*|PY_EXEC="'"$NEOHOST_DIR"'/miniconda3/envs/py27/bin/python2"|' \
    "$NEOHOST_DIR/backend/opt/neohost/backend/neohost.sh"
# Replace Python detection logic (lines 20-31) with LD_LIBRARY_PATH export
sed -i '20,31d' "$NEOHOST_DIR/backend/opt/neohost/backend/neohost.sh"
sed -i '20i export LD_LIBRARY_PATH=${SCRIPTPATH}/common/bin:$LD_LIBRARY_PATH' \
    "$NEOHOST_DIR/backend/opt/neohost/backend/neohost.sh"
# Create src symlink in core directory
ln -sf bin "$NEOHOST_DIR/backend/opt/neohost/backend/core/src"

# Update neohost_core.ini with correct paths
echo "Configuring neohost_core.ini..."
sed -i "s|^search_path.*|search_path = $NEOHOST_DIR/backend/opt/neohost/backend/plugins|" \
    "$NEOHOST_DIR/backend/opt/neohost/backend/neohost_core.ini"
sed -i "s|^logging_properties.*|logging_properties = $NEOHOST_DIR/backend/opt/neohost/backend/neohost_logging.properties|" \
    "$NEOHOST_DIR/backend/opt/neohost/backend/neohost_core.ini"

# Add SDK and Backend to PYTHONPATH
echo "[6/6] Setting up environment..."

# Create wrapper script
cat > "$NEOHOST_DIR/run_neohost.sh" << 'EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PYTHONPATH="$SCRIPT_DIR/sdk/opt/neohost/sdk:$SCRIPT_DIR/backend/opt/neohost/backend:$PYTHONPATH"
export LD_LIBRARY_PATH="$SCRIPT_DIR/backend/opt/neohost/backend/plugins/mftFw:$LD_LIBRARY_PATH"

PYTHON="$SCRIPT_DIR/miniconda3/envs/py27/bin/python"

# Run neohost performance counters
exec sudo -E "$PYTHON" \
    "$SCRIPT_DIR/sdk/opt/neohost/sdk/get_device_performance_counters.py" \
    "$@"
EOF

chmod +x "$NEOHOST_DIR/run_neohost.sh"

echo ""
echo "========================================="
echo "✓ NeoHost SDK installed successfully!"
echo "========================================="
echo ""
echo "Usage:"
echo "  $NEOHOST_DIR/run_neohost.sh --dev-uid=0000:b3:00.0 --get-analysis --run-loop"
echo ""
echo "Installed components:"
echo "  - SDK: $NEOHOST_DIR/sdk/"
echo "  - Backend: $NEOHOST_DIR/backend/"
echo "  - Python 2.7: $NEOHOST_DIR/miniconda3/envs/py27/"
echo ""
