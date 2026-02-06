# Auto Install ESXi

Automated VMware ESXi deployment on bare metal servers using Ansible. Supports both **macOS** and **Linux** control nodes, with provisioning via **Dell iDRAC** and **HPE iLO**.

## Features

- **Cross-Platform**: Works on macOS (Darwin) and Linux (Ubuntu, RHEL, etc.)
- **Multi-Vendor BMC Support**: Dell iDRAC (Redfish API) and HPE iLO
- **Automated ISO Generation**: Creates custom bootable ISOs with embedded Kickstart files
- **Zero-Touch Deployment**: Fully automated from ISO creation to ESXi boot
- **Secure Credentials**: Environment variables or Ansible Vault for secrets

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/SaalimAfsar/Auto_Install_ESXi.git
cd Auto_Install_ESXi
```

### 2. Run Setup Script

The setup script automatically detects your OS and installs all dependencies:

```bash
# macOS
./setup.sh

# Linux (requires sudo)
sudo ./setup.sh
```

This installs:
- **macOS**: xorriso, cdrtools (mkisofs), ansible via Homebrew
- **Linux**: genisoimage, syslinux-utils, xorriso, ansible via apt/yum

### 3. Place Source ESXi ISO

```bash
# macOS
cp /path/to/VMware-ESXi-8.0.x.iso /opt/esxi-deploy/isosrc/

# Linux
sudo cp /path/to/VMware-ESXi-8.0.x.iso /home/deploy/isosrc/
```

### 4. Configure Your Servers

Edit `inventory/host_vars/ilo-esxi` to define your servers:

```yaml
---
hosts:
  - hostName: esxi01.example.com    # ESXi hostname (used for ISO filename)
    esxi_ip: 192.168.1.10           # ESXi management IP
    ilo_ip: 10.0.0.10               # BMC IP (iDRAC/iLO)

  - hostName: esxi02.example.com    # Add more servers as needed
    esxi_ip: 192.168.1.11
    ilo_ip: 10.0.0.11
```

Edit `inventory/group_vars/ilo-esxi` to set network configuration:

```yaml
---
# ESXi Network Configuration
global_vlan_id: 0                    # 0 for untagged, or VLAN ID (e.g., 100)
global_netmask: 255.255.255.0
global_gw: 192.168.1.1
global_dns1: 8.8.8.8
global_dns2: 1.1.1.1
global_ntp1: pool.ntp.org
global_ntp2: time.google.com

# Source ISO filename (must exist in isosrc directory)
src_iso_file: VMware-ESXi-8.0.2-22380479.iso

# ISO serving - CIFS share for Dell iDRAC (recommended)
iso_web_server: //YOUR_SERVER_IP/iso
```

### 5. Set Credentials

**Option A: Environment Variables (Recommended)**

```bash
export ESXI_ROOT_PASSWORD='YourSecurePassword'
export ILO_USER='admin'
export ILO_PASSWORD='BMCPassword'
```

**Option B: Ansible Vault**

```bash
# Create encrypted secrets file
ansible-vault create inventory/group_vars/secrets.yml
```

Add to secrets.yml:
```yaml
vault_root_password: 'YourSecurePassword'
vault_ilo_user: 'admin'
vault_ilo_pass: 'BMCPassword'
```

### 6. Run the Playbook

```bash
# Full deployment (ISO generation + BMC provisioning)
ansible-playbook playbook/00.ilo_iso_esxi.yaml

# ISO generation only
ansible-playbook playbook/00.ilo_iso_esxi.yaml --tags iso

# BMC provisioning only (requires pre-generated ISOs)
ansible-playbook playbook/00.ilo_iso_esxi.yaml --tags ilo

# With Ansible Vault
ansible-playbook playbook/00.ilo_iso_esxi.yaml --ask-vault-pass
```

## Project Structure

```
Auto_Install_ESXi/
├── setup.sh                    # OS-aware setup script
├── ansible.cfg                 # Ansible configuration
├── requirements.yml            # Ansible Galaxy collections
├── requirements.txt            # Python dependencies
├── playbook/
│   └── 00.ilo_iso_esxi.yaml   # Main orchestration playbook
├── inventory/
│   ├── hosts                   # Ansible inventory
│   ├── host_vars/
│   │   └── ilo-esxi           # Per-server configuration
│   └── group_vars/
│       ├── ilo-esxi           # Global settings
│       └── secrets.yml        # Encrypted credentials (create this)
└── roles/
    ├── copy-iso-mount/        # Mount source ISO, copy to staging
    ├── vm-custome-boot/       # Add Kickstart option to boot.cfg
    ├── vm-ks/                 # Generate per-host Kickstart file
    ├── vm-gen-iso/            # Create bootable ISO
    ├── iso-uefi/              # Apply UEFI compatibility
    ├── clean-stage/           # Cleanup staging files
    ├── idrac-provisioning/    # Dell iDRAC provisioning
    └── ilo-provisioning/      # HPE iLO provisioning
```

## Directory Paths by OS

| Purpose | macOS | Linux |
|---------|-------|-------|
| Source ISO | `/opt/esxi-deploy/isosrc/` | `/home/deploy/isosrc/` |
| Staging | `/opt/esxi-deploy/baremetal/` | `/home/deploy/baremetal/` |
| Generated ISOs | `/opt/stageiso/` | `/home/stageiso/` |

## Dell iDRAC Setup

### Enable Virtual Media

Before running the playbook, enable Virtual Media on iDRAC:

**Via Web UI:**
1. iDRAC Web UI → Configuration → Virtual Media
2. Set "Attached Media" to **Attached** or **Auto-Attach**

**Via Redfish API:**
```bash
curl -k -u admin:password -X PATCH \
  https://IDRAC_IP/redfish/v1/Managers/iDRAC.Embedded.1/Attributes \
  -H "Content-Type: application/json" \
  -d '{"Attributes": {"VirtualMedia.1.Enable": "Enabled", "VirtualMedia.1.Attached": "Attached"}}'
```

### CIFS Share Setup (Required for Dell iDRAC)

Dell iDRAC requires CIFS for virtual media. Set up Samba on your file server:

```bash
sudo apt install -y samba

# Add to /etc/samba/smb.conf:
[iso]
    path = /home/stageiso    # or /opt/stageiso on macOS
    guest ok = yes
    read only = yes
    browseable = yes
    force user = nobody
    force group = nogroup

sudo systemctl restart smbd
```

Update `iso_web_server` in group_vars:
```yaml
iso_web_server: //YOUR_SERVER_IP/iso
```

## HPE iLO Setup

HPE iLO supports HTTP for virtual media. Set up a simple web server:

```bash
# Using Python (for testing)
cd /home/stageiso
python3 -m http.server 8080

# Or use nginx/apache for production
```

Update `iso_web_server` in group_vars:
```yaml
iso_web_server: http://YOUR_SERVER_IP:8080
```

## Workflow

1. **ISO Generation** (`--tags iso`):
   ```
   Source ISO → Mount → Modify boot.cfg → Generate Kickstart → Create ISO → UEFI Hybrid → Cleanup
   ```

2. **BMC Provisioning** (`--tags ilo`):
   ```
   Eject Media → Mount ISO → Set Boot Order → Power On → Wait for Install → Eject → Verify ESXi
   ```

## Kickstart Configuration

The generated Kickstart file (`KS.CFG`) configures:

- Accept EULA automatically
- Clear and install to first local disk
- Set root password
- Configure static network (IP, netmask, gateway, DNS, hostname)
- VLAN tagging (if `global_vlan_id > 0`)
- Auto-reboot after installation

**Post-install (firstboot) scripts:**
- Enable and start SSH
- Enable and start ESXi Shell
- Disable IPv6
- Configure NTP servers
- Add secondary DNS

## Troubleshooting

### "Virtual Media is detached"

iDRAC Virtual Media Attach Mode not configured. Run:
```bash
curl -k -u admin:password -X PATCH \
  https://IDRAC_IP/redfish/v1/Managers/iDRAC.Embedded.1/Attributes \
  -H "Content-Type: application/json" \
  -d '{"Attributes": {"VirtualMedia.1.Attached": "Attached"}}'
```

### "Fatal error 15 (Not found)" during boot

boot.cfg module list doesn't match ISO contents. The playbook modifies the original boot.cfg instead of replacing it, ensuring compatibility.

### "cannot find kickstart file on cd-rom with path -- /KS.CFG"

Case sensitivity issue. The playbook preserves `KS.CFG` as uppercase while converting other files to lowercase for ISO9660 compatibility.

### "Remote file location is not accessible"

1. Verify network connectivity between BMC and file server
2. Check firewall rules (CIFS: 445, HTTP: 80/8080)
3. Test CIFS: `smbclient -L //SERVER_IP -N`

### macOS: "xorriso not found"

```bash
brew install xorriso cdrtools
```

### Linux: "genisoimage not found"

```bash
# Ubuntu/Debian
sudo apt install -y genisoimage syslinux-utils

# RHEL/CentOS
sudo yum install -y genisoimage syslinux
```

## Manual BMC Operations

### Eject Virtual Media (iDRAC)
```bash
curl -k -u admin:password -X POST \
  https://IDRAC_IP/redfish/v1/Managers/iDRAC.Embedded.1/VirtualMedia/CD/Actions/VirtualMedia.EjectMedia \
  -H "Content-Type: application/json" -d '{}'
```

### Check Server Power State
```bash
curl -k -u admin:password \
  https://IDRAC_IP/redfish/v1/Systems/System.Embedded.1 | jq '.PowerState'
```

### Restart Server
```bash
curl -k -u admin:password -X POST \
  https://IDRAC_IP/redfish/v1/Systems/System.Embedded.1/Actions/ComputerSystem.Reset \
  -H "Content-Type: application/json" \
  -d '{"ResetType": "ForceRestart"}'
```

## Requirements

### System Packages

| Package | macOS (Homebrew) | Linux (apt) |
|---------|------------------|-------------|
| ISO creation | `cdrtools`, `xorriso` | `genisoimage`, `xorriso` |
| UEFI support | `xorriso` | `syslinux-utils` |
| Automation | `ansible` | `ansible` |

### Python Packages

```
pyvmomi
python-hpilo  # For HPE iLO only
```

### Ansible Collections

```bash
ansible-galaxy collection install -r requirements.yml
```

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

This project is open source. See the repository for license details.

## Acknowledgments

- Original project concept by [salehmiri90](https://github.com/salehmiri90)
- Dell iDRAC Redfish integration added for this fork
- macOS support added by [SaalimAfsar](https://github.com/SaalimAfsar)
