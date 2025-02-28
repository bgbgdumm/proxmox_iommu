#!/bin/bash

# Initialize global variables
REBOOT_REQUIRED=0
DEBUG_MODE=0
DRY_RUN=0

# Function to print debug messages
log() {
    [[ $DEBUG_MODE -eq 1 ]] && echo "[DEBUG] $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root. Please run with sudo."
        exit 1
    fi
}

# Function to detect CPU vendor
detect_cpu() {
    if grep -q "AMD" /proc/cpuinfo; then
        CPU="AMD"
    elif grep -q "Intel" /proc/cpuinfo; then
        CPU="Intel"
    else
        echo "Unsupported CPU vendor. Exiting."
        exit 1
    fi
    log "Detected CPU: $CPU"
}

# Function to safely modify GRUB settings
modify_grub() {
    local key="$1"
    local value="$2"
    
    # Remove existing entry
    sed -i "s/\b$key=[^ \"']*\b//g" /etc/default/grub
    
    # Append new entry
    sed -i "/^GRUB_CMDLINE_LINUX_DEFAULT/ s/\"$/ $key=$value\"/" /etc/default/grub
}

# Function to enable or disable virtualization (IOMMU) and screen timeout
manage_virtualization() {
    read -p "Do you want to enable virtualization and screen timeout? (y/n): " ENABLE_VIRT
    if [[ "$ENABLE_VIRT" == "y" ]]; then
        read -p "Enter screen turnoff time in seconds (default: 60): " SCREEN_TIMEOUT
        SCREEN_TIMEOUT=${SCREEN_TIMEOUT:-60}

        if [[ "$CPU" == "AMD" ]]; then
            log "Enabling AMD IOMMU..."
            modify_grub "amd_iommu" "on"
            modify_grub "iommu" "pt"
        else
            log "Enabling Intel IOMMU..."
            modify_grub "intel_iommu" "on"
            modify_grub "iommu" "pt"
        fi
        modify_grub "consoleblank" "$SCREEN_TIMEOUT"

        $DRY_RUN || update-grub || echo "[ERROR] Failed to update GRUB!"
        $DRY_RUN || setterm -blank "$((SCREEN_TIMEOUT / 60))"
        REBOOT_REQUIRED=1
    else
        log "Disabling IOMMU..."
        sed -i 's/\bamd_iommu=on\b//g; s/\biommu=pt\b//g; s/\bintel_iommu=on\b//g' /etc/default/grub
        $DRY_RUN || update-grub || echo "[ERROR] Failed to update GRUB!"
        REBOOT_REQUIRED=1
    fi
}

# Function to manage PCI passthrough modules
manage_pci_passthrough() {
    MODULES_FILE="/etc/modules"
    MODULES=("vfio" "vfio_iommu_type1" "vfio_pci" "vfio_virqfd")
    
    read -p "Enable PCI passthrough? (y/n): " ENABLE_PCI
    if [[ "$ENABLE_PCI" == "y" ]]; then
        log "Enabling PCI passthrough..."
        for module in "${MODULES[@]}"; do
            $DRY_RUN || modprobe "$module" || echo "[ERROR] Failed to load $module"
            grep -qxF "$module" "$MODULES_FILE" || echo "$module" >> "$MODULES_FILE"
        done
    else
        log "Disabling PCI passthrough..."
        for module in "${MODULES[@]}"; do
            $DRY_RUN || modprobe -r "$module"
            sed -i "/^$module$/d" "$MODULES_FILE"
        done
    fi
}

# Function to manage lid switch behavior
manage_lid_switch() {
    LOGIND_CONF="/etc/systemd/logind.conf"
    read -p "Ignore laptop lid closing? (y/n): " ENABLE_LID
    if [[ "$ENABLE_LID" == "y" ]]; then
        log "Ignoring laptop lid switch..."
        sed -i '/^HandleLidSwitch=/d' "$LOGIND_CONF"
        echo "HandleLidSwitch=ignore" >> "$LOGIND_CONF"
    else
        log "Restoring default lid switch behavior..."
        sed -i '/^HandleLidSwitch=ignore/d' "$LOGIND_CONF"
    fi
    $DRY_RUN || systemctl restart systemd-logind
}

# Menu
check_root

detect_cpu

echo "Choose an option:"
echo "1) Manage Virtualization & Screen Timeout"
echo "2) Manage PCI Passthrough Modules"
echo "3) Manage Laptop Lid Switch Behavior"
echo "4) Apply All Settings"
echo "5) Enable Debug Mode"
echo "6) Enable Dry Run Mode (No Changes Applied)"
echo "7) Exit"

read -p "Enter your choice: " choice

case $choice in
    1) manage_virtualization ;;
    2) manage_pci_passthrough ;;
    3) manage_lid_switch ;;
    4)
        manage_virtualization
        manage_pci_passthrough
        manage_lid_switch
        ;;
    5) DEBUG_MODE=1; echo "Debug mode enabled!" ;;
    6) DRY_RUN=1; echo "Dry run mode enabled! No changes will be made." ;;
    7) echo "Exiting..."; exit 0 ;;
    *) echo "Invalid choice, exiting."; exit 1 ;;
esac

# Ask for reboot if necessary
if [[ $REBOOT_REQUIRED -eq 1 ]]; then
    read -p "A reboot is required for all changes to take full effect. Reboot now? (y/n): " REBOOT_NOW
    if [[ "$REBOOT_NOW" == "y" ]]; then
        echo "Rebooting now..."
        reboot
    else
        echo "Reboot later for changes to take full effect."
    fi
else
    echo "All changes applied without reboot!"
fi
