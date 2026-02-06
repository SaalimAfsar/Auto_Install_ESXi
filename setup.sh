#!/bin/bash
# Setup script for Auto_Install_ESXi Ansible project
# This script installs all required dependencies and sets up the environment

# Don't exit on errors - we'll handle them gracefully
set +e

echo "========================================="
echo "Auto_Install_ESXi Setup Script"
echo "========================================="
echo ""

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then 
    echo "This script requires sudo privileges. Please run with sudo or as root."
    echo "Usage: sudo ./setup.sh"
    exit 1
fi

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    echo "Cannot detect OS. Exiting."
    exit 1
fi

echo "Detected OS: $OS $VER"
echo ""

# Function to update apt with error handling
update_apt() {
    echo "Updating package lists (ignoring repository errors)..."
    # Run apt-get update, but don't fail on repository errors
    # Filter out specific repository warning/error messages for cleaner output
    # We still want to see other important errors
    apt-get update 2>&1 | \
        grep -v "NO_PUBKEY" | \
        grep -v "is not signed" | \
        grep -v "W: Target" | \
        grep -v "W: GPG error" | \
        grep -v "E: The repository" | \
        grep -v "N: Updating from such a repository" || true
    
    # Always return success - package installations can still work
    # even if some repositories have issues
    return 0
}

# Install Python and pip if not present
echo "Step 1: Installing Python3 and pip..."
if command -v python3 &> /dev/null; then
    echo "Python3 is already installed: $(python3 --version)"
    # Check if pip3 is available, if not install it
    if ! command -v pip3 &> /dev/null && ! python3 -m pip --version &> /dev/null; then
        echo "pip3 not found. Installing python3-pip..."
        if [ "$OS" == "ubuntu" ] || [ "$OS" == "debian" ]; then
            update_apt
            apt-get install -y python3-pip
        elif [ "$OS" == "rhel" ] || [ "$OS" == "centos" ] || [ "$OS" == "fedora" ]; then
            if [ "$OS" == "fedora" ]; then
                dnf install -y python3-pip
            else
                yum install -y python3-pip
            fi
        fi
    fi
else
    if [ "$OS" == "ubuntu" ] || [ "$OS" == "debian" ]; then
        update_apt
        apt-get install -y python3 python3-pip python3-venv
    elif [ "$OS" == "rhel" ] || [ "$OS" == "centos" ] || [ "$OS" == "fedora" ]; then
        if [ "$OS" == "fedora" ]; then
            dnf install -y python3 python3-pip
        else
            yum install -y python3 python3-pip
        fi
    fi
fi

# Verify pip is available (either as pip3 command or python3 -m pip)
if command -v pip3 &> /dev/null; then
    PIP_CMD="pip3"
    echo "pip3 command found: $(pip3 --version)"
elif python3 -m pip --version &> /dev/null; then
    PIP_CMD="python3 -m pip"
    echo "Using python3 -m pip: $(python3 -m pip --version)"
else
    echo "Error: pip3 is not available and could not be installed."
    echo "Please install python3-pip manually: sudo apt install python3-pip"
    exit 1
fi

# Install system packages required for ISO generation
echo ""
echo "Step 2: Installing system packages (mkisofs, isohybrid, etc.)..."
if [ "$OS" == "ubuntu" ] || [ "$OS" == "debian" ]; then
    update_apt
    apt-get install -y genisoimage syslinux-utils || {
        echo "Warning: Some packages may have failed to install due to repository issues."
        echo "You may need to fix repository GPG keys manually."
    }
elif [ "$OS" == "rhel" ] || [ "$OS" == "centos" ] || [ "$OS" == "fedora" ]; then
    if [ "$OS" == "fedora" ]; then
        dnf install -y genisoimage syslinux
    else
        yum install -y genisoimage syslinux
    fi
fi

# Install Ansible
echo ""
echo "Step 3: Installing Ansible..."
if command -v ansible &> /dev/null; then
    echo "Ansible is already installed: $(ansible --version | head -n 1)"
else
    if [ "$OS" == "ubuntu" ] || [ "$OS" == "debian" ]; then
        apt-get install -y software-properties-common || true
        apt-add-repository --yes --update ppa:ansible/ansible || {
            echo "Warning: Failed to add Ansible PPA. Trying alternative installation method..."
            # Try installing from pip as fallback
            $PIP_CMD install ansible || {
                echo "Error: Could not install Ansible. Please install manually."
                exit 1
            }
        }
        if ! command -v ansible &> /dev/null; then
            update_apt
            apt-get install -y ansible || {
                echo "Warning: apt-get install failed. Trying pip installation..."
                $PIP_CMD install ansible
            }
        fi
    elif [ "$OS" == "rhel" ] || [ "$OS" == "centos" ]; then
        yum install -y epel-release
        yum install -y ansible
    elif [ "$OS" == "fedora" ]; then
        dnf install -y ansible
    fi
fi

# Install Python packages
echo ""
echo "Step 4: Installing Python packages (pyvmomi, VMware SDK, python-hpilo)..."
$PIP_CMD install --upgrade pip || {
    echo "Warning: Failed to upgrade pip. Continuing..."
}
$PIP_CMD install pyvmomi || {
    echo "Error: Failed to install pyvmomi. Please check your internet connection."
    echo "You can try installing manually: $PIP_CMD install pyvmomi"
    exit 1
}
$PIP_CMD install git+https://github.com/vmware/vsphere-automation-sdk-python.git || {
    echo "Warning: Failed to install VMware SDK. You may need to install it manually."
    echo "You can try: $PIP_CMD install git+https://github.com/vmware/vsphere-automation-sdk-python.git"
}
$PIP_CMD install python-hpilo || {
    echo "Warning: Failed to install python-hpilo. This is required for iLO operations."
    echo "You can try: $PIP_CMD install python-hpilo"
}

# Install Ansible collections
echo ""
echo "Step 5: Installing Ansible collections..."
if command -v ansible-galaxy &> /dev/null; then
    ansible-galaxy collection install community.general || {
        echo "Warning: Failed to install community.general collection"
    }
    ansible-galaxy collection install hpe.ilo || {
        echo "Warning: Failed to install hpe.ilo collection"
        echo "You may need to install it manually: ansible-galaxy collection install hpe.ilo"
    }
else
    echo "Error: ansible-galaxy not found. Ansible may not be installed correctly."
    exit 1
fi

# Create necessary directories
echo ""
echo "Step 6: Creating required directories..."
mkdir -p /home/deploy/isosrc
mkdir -p /home/deploy/baremetal
mkdir -p /home/stageiso
mkdir -p /mnt
chmod 755 /home/deploy/isosrc
chmod 755 /home/deploy/baremetal
chmod 755 /home/stageiso

# Create log directory
mkdir -p $(dirname $(grep "^log_path" ansible.cfg 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "./log/ansible.log"))
mkdir -p ./log

# Re-enable error checking for final verification
set -e

echo ""
echo "========================================="
if command -v ansible &> /dev/null && command -v ansible-galaxy &> /dev/null; then
    echo "Setup completed successfully!"
else
    echo "Setup completed with warnings!"
    echo "Please verify Ansible installation: ansible --version"
fi
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Place your ESXi ISO file in: /home/deploy/isosrc/"
echo "2. Update inventory/group_vars/ilo-esxi with your configuration"
echo "3. Update inventory/host_vars/ilo-esxi with your server details"
echo "4. Ensure your web server can serve ISOs from: /home/stageiso/"
echo "5. Run the playbook: ansible-playbook playbook/00.ilo_iso_esxi.yaml"
echo ""
