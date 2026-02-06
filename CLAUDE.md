# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Auto_Install_ESXi automates VMware ESXi 8.0.x deployment on bare metal servers (HPE iLO and Dell iDRAC) using Ansible and Kickstart files. It creates custom bootable ISOs with embedded configuration and boots servers via BMC virtual media.

**Supported Platforms:** Ubuntu/Debian, RHEL/CentOS/Fedora, and macOS

## Prerequisites

### Quick Setup (Recommended)
The setup script automatically detects your OS and installs all dependencies:
```bash
# Linux
sudo ./setup.sh

# macOS (no sudo needed for Homebrew)
./setup.sh
```

### Manual Installation

#### Ubuntu/Debian
```bash
sudo apt install -y python3 python3-pip genisoimage syslinux-utils xorriso ansible
pip3 install pyvmomi python-hpilo
```

#### macOS (via Homebrew)
```bash
brew install python3 cdrtools xorriso ansible
pip3 install pyvmomi python-hpilo
```

### Ansible Collections
```bash
ansible-galaxy collection install -r requirements.yml
```

### Directory Structure

The playbook auto-detects your OS and uses appropriate paths:

| Purpose | Linux Path | macOS Path |
|---------|-----------|------------|
| Source ESXi ISO | `/home/deploy/isosrc/` | `/opt/esxi-deploy/isosrc/` |
| Staging directory | `/home/deploy/baremetal/` | `/opt/esxi-deploy/baremetal/` |
| Generated ISOs | `/home/stageiso/` | `/opt/stageiso/` |
| Mount points | `/mnt/` | `/Volumes/esxi-mount/` |

The setup script creates these directories automatically. To create manually:

**Linux:**
```bash
sudo mkdir -p /home/deploy/isosrc /home/deploy/baremetal /home/stageiso
sudo chmod 755 /home/stageiso
```

**macOS:**
```bash
sudo mkdir -p /opt/esxi-deploy/isosrc /opt/esxi-deploy/baremetal /opt/stageiso
sudo chmod 755 /opt/stageiso
sudo chown -R $(whoami):staff /opt/esxi-deploy /opt/stageiso
```

### CIFS Share Setup (Required for Dell iDRAC)
Dell iDRAC requires CIFS for virtual media. Set up Samba:
```bash
sudo apt install -y samba

# Add to /etc/samba/smb.conf:
[iso]
    path = /home/stageiso
    guest ok = yes
    read only = yes
    browseable = yes
    force user = nobody
    force group = nogroup

sudo systemctl restart smbd
```

### iDRAC Configuration (Dell Servers)
Before running the playbook, ensure iDRAC Virtual Media is enabled:
1. iDRAC Web UI → Configuration → Virtual Media
2. Set "Attached Media" to **Attached** or **Auto-Attach**
3. Or via Redfish API:
```bash
curl -k -u admin:password -X PATCH \
  https://IDRAC_IP/redfish/v1/Managers/iDRAC.Embedded.1/Attributes \
  -H "Content-Type: application/json" \
  -d '{"Attributes": {"VirtualMedia.1.Enable": "Enabled", "VirtualMedia.1.Attached": "Attached"}}'
```

## Commands

```bash
# Setup (run once)
# Linux:
sudo ./setup.sh
# macOS:
./setup.sh

ansible-galaxy collection install -r requirements.yml

# Full deployment (ISO generation + BMC provisioning)
sudo ansible-playbook playbook/00.ilo_iso_esxi.yaml

# ISO generation only
sudo ansible-playbook playbook/00.ilo_iso_esxi.yaml --tags iso

# BMC provisioning only (requires pre-generated ISOs)
sudo ansible-playbook playbook/00.ilo_iso_esxi.yaml --tags ilo

# Syntax check
ansible-playbook playbook/00.ilo_iso_esxi.yaml --syntax-check

# Verify generated ISOs
# Linux:
ls -lh /home/stageiso/*.iso
# macOS:
ls -lh /opt/stageiso/*.iso
```

## Configuration

### Step 1: Place Source ESXi ISO
```bash
# Linux:
cp VMware-ESXi-8.0.2-*.iso /home/deploy/isosrc/

# macOS:
cp VMware-ESXi-8.0.2-*.iso /opt/esxi-deploy/isosrc/
```

### Step 2: Configure Host Variables
Edit `inventory/host_vars/ilo-esxi`:
```yaml
hosts:
  - hostName: esxi01.example.com    # ESXi hostname (also used for ISO filename)
    esxi_ip: 192.168.1.10           # Management IP for ESXi
    ilo_ip: 10.0.0.10               # BMC/iLO/iDRAC IP address

  - hostName: esxi02.example.com    # Add more servers as needed
    esxi_ip: 192.168.1.11
    ilo_ip: 10.0.0.11
```

### Step 3: Configure Group Variables
Edit `inventory/group_vars/ilo-esxi`:
```yaml
# OS-aware paths (auto-detected, override if needed)
# deploy_base_path: /home/deploy      # Linux default
# deploy_base_path: /opt/esxi-deploy  # macOS default
# iso_stage_path: /home/stageiso      # Linux default
# iso_stage_path: /opt/stageiso       # macOS default

# ESXi Configuration
root_password: 'YourSecurePassword'
global_vlan_id: 0                    # Set to 0 for untagged, or VLAN ID (e.g., 100)
global_netmask: 255.255.255.0
global_gw: 192.168.1.1
global_dns1: 8.8.8.8
global_dns2: 1.1.1.1
global_ntp1: pool.ntp.org
global_ntp2: time.google.com

# BMC Credentials (iLO/iDRAC)
ilo_user: admin
ilo_pass: 'BMCPassword'
ilo_state: boot_once

# Source ISO filename (must exist in isosrc directory)
src_iso_file: VMware-ESXi-8.0.2-22380479-HPE-802.0.0.11.5.0.6-Oct2023.iso

# ISO serving method - CIFS share path (recommended for Dell iDRAC)
iso_web_server: //10.201.1.103/iso
# Alternative: HTTP (may not work with all iDRAC versions)
# iso_web_server: http://10.201.1.103:8080
```

## Architecture

### Workflow
1. **ISO Generation** (`--tags iso`):
   - Mount source ESXi ISO (Linux: `mount -o loop`, macOS: `hdiutil attach`)
   - Modify boot.cfg to add Kickstart option
   - Generate per-host Kickstart file with network config
   - Repackage ISO (Linux: `genisoimage`, macOS: `mkisofs`)
   - Apply UEFI compatibility (Linux: `isohybrid`, macOS: `xorriso`)
   - Cleanup staging files

2. **BMC Provisioning** (`--tags ilo`):
   - Eject any existing virtual media
   - Mount custom ISO via CIFS/HTTP
   - Set one-time boot to virtual CD
   - Power on/restart server
   - Wait for installation to complete
   - Eject virtual media
   - Verify ESXi is reachable

### Key Files
- `playbook/00.ilo_iso_esxi.yaml` - Main orchestration playbook
- `inventory/host_vars/ilo-esxi` - Per-server config
- `inventory/group_vars/ilo-esxi` - Global settings
- `roles/vm-ks/tasks/main.yml` - Kickstart template
- `roles/idrac-provisioning/tasks/main.yml` - Dell iDRAC provisioning
- `roles/ilo-provisioning/tasks/main.yml` - HPE iLO provisioning

### Roles Execution Order
1. `copy-iso-mount` - Mount source ISO, copy to staging
2. `vm-custome-boot` - Add Kickstart option to boot.cfg
3. `vm-ks` - Generate per-host KS.CFG
4. `vm-gen-iso` - Create bootable ISO
5. `iso-uefi` - Apply isohybrid for UEFI
6. `clean-stage` - Cleanup staging files
7. `idrac-provisioning` or `ilo-provisioning` - Boot server via BMC

## Kickstart Configuration

The Kickstart file (`roles/vm-ks/tasks/main.yml`) configures:
- Accepts EULA automatically
- Clears and installs to first local disk
- Sets root password
- Configures static network (IP, netmask, gateway, DNS, hostname)
- VLAN tagging (if `global_vlan_id > 0`)
- Auto-reboot after installation (`reboot --noeject`)

**Post-install (firstboot) scripts:**
- Enable and start SSH
- Enable and start ESXi Shell
- Disable IPv6
- Configure NTP servers
- Add secondary DNS

## Troubleshooting

### Error: "Virtual Media is detached"
**Cause:** iDRAC Virtual Media Attach Mode not configured
**Fix:**
```bash
curl -k -u admin:password -X PATCH \
  https://IDRAC_IP/redfish/v1/Managers/iDRAC.Embedded.1/Attributes \
  -H "Content-Type: application/json" \
  -d '{"Attributes": {"VirtualMedia.1.Enable": "Enabled", "VirtualMedia.1.Attached": "Attached"}}'
```

### Error: "Fatal error 15" during boot
**Cause:** boot.cfg module list doesn't match ISO contents (version mismatch)
**Fix:** The playbook now modifies the original boot.cfg instead of replacing it, ensuring compatibility with any ESXi version.

### Error: Network not configured after installation
**Cause:** VLAN ID 0 being passed to Kickstart
**Fix:** The playbook now conditionally includes `--vlanid` only when `global_vlan_id > 0`.

### Error: "Remote file location is not accessible"
**Cause:** iDRAC cannot reach the file server
**Fix:**
1. Verify network connectivity between iDRAC and file server
2. Check firewall rules
3. For CIFS: Ensure Samba is running and share is accessible
4. Test: `smbclient -L //SERVER_IP -N`

### Error: Installation hangs at "Remove media and press Enter"
**Cause:** Missing `reboot --noeject` in Kickstart
**Fix:** Already included in current Kickstart template.

### Error: Boot fails partway through loading modules
**Cause:** Virtual media connection unstable (common with large files over network)
**Fix:**
1. Use CIFS instead of HTTP for more reliable transfers
2. Ensure stable network between iDRAC and file server
3. Check iDRAC firmware is up to date

## Manual Operations

### Eject Virtual Media
```bash
curl -k -u admin:password -X POST \
  https://IDRAC_IP/redfish/v1/Managers/iDRAC.Embedded.1/VirtualMedia/CD/Actions/VirtualMedia.EjectMedia \
  -H "Content-Type: application/json" -d '{}'
```

### Mount ISO Manually
```bash
curl -k -u admin:password -X POST \
  https://IDRAC_IP/redfish/v1/Managers/iDRAC.Embedded.1/VirtualMedia/CD/Actions/VirtualMedia.InsertMedia \
  -H "Content-Type: application/json" \
  -d '{"Image": "//FILE_SERVER/iso/hostname.iso", "Inserted": true, "WriteProtected": true}'
```

### Set One-Time Boot to CD
```bash
curl -k -u admin:password -X PATCH \
  https://IDRAC_IP/redfish/v1/Systems/System.Embedded.1 \
  -H "Content-Type: application/json" \
  -d '{"Boot": {"BootSourceOverrideEnabled": "Once", "BootSourceOverrideTarget": "Cd", "BootSourceOverrideMode": "UEFI"}}'
```

### Restart Server
```bash
curl -k -u admin:password -X POST \
  https://IDRAC_IP/redfish/v1/Systems/System.Embedded.1/Actions/ComputerSystem.Reset \
  -H "Content-Type: application/json" \
  -d '{"ResetType": "ForceRestart"}'
```

### Check Server Power State
```bash
curl -k -u admin:password \
  https://IDRAC_IP/redfish/v1/Systems/System.Embedded.1 | python3 -m json.tool | grep PowerState
```

## Notes

- Playbook includes retry logic (up to 3 attempts) for failed installations
- Installation typically takes 8-12 minutes depending on hardware
- Servers can be powered on or off before running the playbook
- ISO filenames match hostnames (e.g., `esxi01.example.com.iso`)
- Generated ISOs are stored in `/home/stageiso/` (Linux) or `/opt/stageiso/` (macOS)
- The playbook auto-detects OS and uses appropriate tools/paths
- macOS support requires Homebrew for package management

## Network Requirements

### VPN Access
- **iDRAC/iLO BMC network** typically requires VPN access
- Ensure VPN is connected before running provisioning (`--tags ilo`)
- The control machine must be able to reach both:
  - BMC IP (iDRAC/iLO) for Redfish API commands
  - ESXi management IP for verification (optional)

## Platform-Specific Notes

### macOS
- Uses `hdiutil` for ISO mounting (instead of `mount -o loop`)
- Uses `mkisofs` from cdrtools (instead of `genisoimage`)
- Uses `xorriso` for UEFI compatibility (instead of `isohybrid`)
- Paths default to `/opt/esxi-deploy/` and `/opt/stageiso/`
- Setup script installs packages via Homebrew

### Linux (Ubuntu/Debian/RHEL)
- Uses standard Linux mount commands
- Uses `genisoimage` and `isohybrid` from syslinux-utils
- Paths default to `/home/deploy/` and `/home/stageiso/`
