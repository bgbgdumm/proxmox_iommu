#!/bin/bash

# Global Variables
REBOOT_REQUIRED=0
GRUB_FILE="/etc/default/grub"
GRUB_BACKUP="/etc/default/grub.bak"
MODULES_FILE="/etc/modules"
LOGIND_CONF="/etc/systemd/logind.conf"
PROXMOX_LOG="/var/log/proxmox_tweaks.log"

# Function to log messages
to_log() {
    echo "$(date) - $1" | tee -a "$PROXMOX_LOG"
}

# Ensure script is run as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        to_log "This script must be run as root. Please use sudo."
        exit 1
    fi
}

# Check for required commands
check_dependencies() {
    for cmd in grep sed update-initramfs systemctl; do
        if ! command -v $cmd &>/dev/null; then
            to_log "Missing required command: $cmd. Install it and try again."
            exit 1
        fi
    done
}

# Detect CPU vendor
detect_cpu() {
    if grep -q "AMD" /proc/cpuinfo; then
        CPU="AMD"
    elif grep -q "Intel" /proc/cpuinfo; then
        CPU="Intel"
    else
        to_log "Unsupported CPU vendor. Exiting."
        exit 1
    fi
    to_log "Detected CPU: $CPU"
}

# Check for hardware support (VT-d / AMD-V)
check_hardware_support() {
    if [[ "$CPU" == "AMD" && -z $(grep -E "(svm)" /proc/cpuinfo) ]]; then
        to_log "Warning: AMD-V not supported or disabled in BIOS."
    elif [[ "$CPU" == "Intel" && -z $(grep -E "(vmx)" /proc/cpuinfo) ]]; then
        to_log "Warning: VT-d not supported or disabled in BIOS."
    else
        to_log "IOMMU is supported on this system."
    fi
}

# Modify GRUB parameters safely
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

# Backup & restore GRUB
backup_grub() {
    cp "$GRUB_FILE" "$GRUB_BACKUP"
    to_log "GRUB configuration backed up."
}
restore_grub() {
    if [[ -f "$GRUB_BACKUP" ]]; then
        cp "$GRUB_BACKUP" "$GRUB_FILE"
        update-grub
        to_log "GRUB restored from backup. A reboot is required."
        REBOOT_REQUIRED=1
    else
        to_log "No backup found. Cannot restore."
    fi
}

# Apply recommended settings
apply_recommended() {
    to_log "Applying recommended settings..."
    modify_grub "iommu" "pt"
    modify_grub "${CPU,,}_iommu" "on"
    modify_grub "pcie_acs_override" "downstream,multifunction"
    echo -e "vfio\nvfio_iommu_type1\nvfio_pci\nvfio_virqfd" > "$MODULES_FILE"
    update-initramfs -u
    REBOOT_REQUIRED=1
}

# Reset all tweaks
reset_tweaks() {
    to_log "Resetting all modifications..."
    restore_grub
    sed -i "/^vfio/d" "$MODULES_FILE"
    update-initramfs -u
    to_log "All modifications reset. A reboot is required."
    REBOOT_REQUIRED=1
}

# View logs
view_logs() {
    cat "$PROXMOX_LOG" | less
}

# Menu
echo "Initializing..."
check_root
check_dependencies
detect_cpu
check_hardware_support
backup_grub

while true; do
    echo -e "\nMenu:"
    echo "1) Enable IOMMU"
    echo "2) Enable ACS Override"
    echo "3) Enable PCI Passthrough"
    echo "4) Apply Recommended Settings"
    echo "5) Reset All Modifications"
    echo "6) Restore GRUB from Backup"
    echo "7) View Logs"
    echo "8) Exit"
    read -p "Enter your choice: " CHOICE

    case "$CHOICE" in
        1) modify_grub "${CPU,,}_iommu" "on"; modify_grub "iommu" "pt";;
        2) modify_grub "pcie_acs_override" "downstream,multifunction";;
        3) echo -e "vfio\nvfio_iommu_type1\nvfio_pci\nvfio_virqfd" > "$MODULES_FILE"; update-initramfs -u;;
        4) apply_recommended;;
        5) reset_tweaks;;
        6) restore_grub;;
        7) view_logs;;
        8) [[ "$REBOOT_REQUIRED" -eq 1 ]] && echo "Reboot required!"; exit 0;;
        *) echo "Invalid option. Try again.";;
    esac

done
