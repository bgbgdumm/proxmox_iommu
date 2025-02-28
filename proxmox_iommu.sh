#!/bin/bash

# Initialize global variables
REBOOT_REQUIRED=0
GRUB_FILE="/etc/default/grub"
MODULES_FILE="/etc/modules"
LOGIND_CONF="/etc/systemd/logind.conf"
PROXMOX_LOG="/var/log/proxmox_script.log"
GRUB_BACKUP="/etc/default/grub.bak"
MODULES_BACKUP="/etc/modules.bak"
LOGIND_BACKUP="/etc/systemd/logind.conf.bak"

# Function to log messages
to_log() {
    echo "$(date) - $1" | tee -a "$PROXMOX_LOG"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        to_log "This script must be run as root. Please run with sudo."
        exit 1
    fi
}

# Function to detect CPU vendor
detect_cpu() {
    local cpu_info=$(grep -m1 "vendor_id" /proc/cpuinfo)
    if [[ $cpu_info == *"AMD"* ]]; then
        CPU="AMD"
    elif [[ $cpu_info == *"Intel"* ]]; then
        CPU="Intel"
    else
        to_log "Unsupported CPU vendor. Exiting."
        exit 1
    fi
    to_log "Detected CPU: $CPU"
}

# Function to create backups only if they do not exist
backup_configs() {
    [[ ! -f "$GRUB_BACKUP" ]] && cp "$GRUB_FILE" "$GRUB_BACKUP" && to_log "Backed up GRUB."
    [[ ! -f "$MODULES_BACKUP" ]] && cp "$MODULES_FILE" "$MODULES_BACKUP" && to_log "Backed up /etc/modules."
    [[ ! -f "$LOGIND_BACKUP" ]] && cp "$LOGIND_CONF" "$LOGIND_BACKUP" && to_log "Backed up logind.conf."
}

# Function to restore defaults
restore_defaults() {
    [[ -f "$GRUB_BACKUP" ]] && cp "$GRUB_BACKUP" "$GRUB_FILE" && to_log "Restored GRUB."
    [[ -f "$MODULES_BACKUP" ]] && cp "$MODULES_BACKUP" "$MODULES_FILE" && to_log "Restored /etc/modules."
    [[ -f "$LOGIND_BACKUP" ]] && cp "$LOGIND_BACKUP" "$LOGIND_CONF" && to_log "Restored logind.conf."
    update-initramfs -u
    to_log "System settings restored. Reboot required."
    REBOOT_REQUIRED=1
}

# Function to modify GRUB safely
modify_grub() {
    local param="$1"
    local value="$2"
    if grep -q "\b$param=[^ ]*" "$GRUB_FILE"; then
        sed -i "s/\b$param=[^ ]*/$param=$value/" "$GRUB_FILE"
    else
        sed -i "/^GRUB_CMDLINE_LINUX_DEFAULT/ s/\"$/ $param=$value\"/" "$GRUB_FILE"
    fi
    REBOOT_REQUIRED=1
    to_log "Modified GRUB: $param=$value"
}

# Other functions remain unchanged...

# Menu
check_root
detect_cpu
backup_configs

while true; do
    echo -e "\nDetected CPU: $CPU"
    echo "1) Manage IOMMU"
    echo "2) Manage ACS Override"
    echo "3) Manage SR-IOV"
    echo "4) Manage Screen Timeout"
    echo "5) Manage PCI Passthrough Modules"
    echo "6) Manage Laptop Lid Switch Behavior"
    echo "7) Apply Recommended Settings"
    echo "8) Restore Default Settings"
    echo "9) View Logs"
    echo "10) Exit"
    read -p "Enter your choice: " CHOICE

    case "$CHOICE" in
        1) manage_iommu ;;
        2) manage_acs_override ;;
        3) manage_sriov ;;
        4) manage_screen_timeout ;;
        5) manage_pci_passthrough ;;
        6) manage_lid_switch ;;
        7) apply_recommended_settings ;;
        8) restore_defaults ;;
        9) cat "$PROXMOX_LOG" ;;
        10) exit 0 ;;
        *) echo "Invalid option. Please try again." ;;
    esac
done
