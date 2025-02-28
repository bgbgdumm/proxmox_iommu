#!/bin/bash

# Initialize global variables
REBOOT_REQUIRED=0
GRUB_FILE="/etc/default/grub"
GRUB_BACKUP="/etc/default/grub.bak"
MODULES_FILE="/etc/modules"
LOGIND_CONF="/etc/systemd/logind.conf"
PROXMOX_LOG="/var/log/proxmox_tuning.log"

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

# Function to create a backup of GRUB
backup_grub() {
    if [[ ! -f "$GRUB_BACKUP" ]]; then
        cp "$GRUB_FILE" "$GRUB_BACKUP"
        to_log "GRUB configuration backed up."
    fi
}

# Function to restore GRUB from backup
restore_grub() {
    if [[ -f "$GRUB_BACKUP" ]]; then
        cp "$GRUB_BACKUP" "$GRUB_FILE"
        update-grub
        to_log "GRUB restored from backup. Reboot required."
        REBOOT_REQUIRED=1
    else
        to_log "No GRUB backup found."
    fi
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

# Function to check IOMMU support
check_iommu_support() {
    if find /sys/kernel/iommu_groups -type l | grep -q .; then
        to_log "IOMMU is supported on this system."
    else
        to_log "IOMMU is not supported. Some features may not work."
    fi
}

# Function to apply recommended settings
apply_recommended() {
    to_log "Applying recommended settings..."
    modify_grub "iommu" "pt"
    modify_grub "$CPU_iommu" "on"
    modify_grub "pcie_acs_override" "downstream,multifunction"
    manage_pci_passthrough "enable"
    manage_lid_switch "enable"
    update-initramfs -u
    to_log "Recommended settings applied. Reboot required."
    REBOOT_REQUIRED=1
}

# Function to view logs
view_logs() {
    if [[ -f "$PROXMOX_LOG" ]]; then
        cat "$PROXMOX_LOG"
    else
        to_log "No logs found."
    fi
}

# Function to revert all changes
reset_settings() {
    restore_grub
    sed -i '/vfio\|vfio_iommu_type1\|vfio_pci\|vfio_virqfd/d' "$MODULES_FILE"
    update-initramfs -u
    to_log "All changes reverted to default settings. Reboot required."
    REBOOT_REQUIRED=1
}

# Menu
check_root
backup_grub
detect_cpu
check_iommu_support

while true; do
    echo -e "\nDetected CPU: $CPU"
    echo "1) Manage IOMMU"
    echo "2) Manage ACS Override"
    echo "3) Manage SR-IOV"
    echo "4) Manage PCI Passthrough Modules"
    echo "5) Manage Laptop Lid Switch Behavior"
    echo "6) Apply Recommended Settings"
    echo "7) Restore GRUB from Backup"
    echo "8) View Logs"
    echo "9) Reset All Settings"
    echo "10) Exit"
    read -p "Enter your choice: " CHOICE

    case "$CHOICE" in
        1) manage_iommu ;;
        2) manage_acs_override ;;
        3) manage_sriov ;;
        4) manage_pci_passthrough ;;
        5) manage_lid_switch ;;
        6) apply_recommended ;;
        7) restore_grub ;;
        8) view_logs ;;
        9) reset_settings ;;
        10) exit 0 ;;
        *) echo "Invalid option. Please try again." ;;
    esac

done
