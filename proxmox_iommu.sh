#!/bin/bash

# Initialize global variables
REBOOT_REQUIRED=0
GRUB_FILE="/etc/default/grub"
MODULES_FILE="/etc/modules"
LOGIND_CONF="/etc/systemd/logind.conf"
PROXMOX_LOG="/var/log/syslog"

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

# Function to enable/disable IOMMU
manage_iommu() {
    to_log "Configuring IOMMU..."
    read -p "Enable IOMMU? (y/n): " ENABLE_IOMMU
    if [[ "$ENABLE_IOMMU" == "y" ]]; then
        if [[ "$CPU" == "AMD" ]]; then
            modify_grub "amd_iommu" "on"
            modify_grub "iommu" "pt"
        else
            modify_grub "intel_iommu" "on"
            modify_grub "iommu" "pt"
        fi
    else
        modify_grub "amd_iommu" "off"
        modify_grub "intel_iommu" "off"
        modify_grub "iommu" "off"
    fi
}

# Function to enable/disable ACS override
manage_acs_override() {
    to_log "Configuring ACS Override..."
    read -p "Enable ACS Override? (y/n): " ENABLE_ACS
    if [[ "$ENABLE_ACS" == "y" ]]; then
        modify_grub "pcie_acs_override" "downstream,multifunction"
    else
        sed -i "s/\bpcie_acs_override=[^ ]*//g" "$GRUB_FILE"
    fi
}

# Function to enable/disable SR-IOV
manage_sriov() {
    to_log "Configuring SR-IOV..."
    read -p "Enable SR-IOV? (y/n): " ENABLE_SRIOV
    if [[ "$ENABLE_SRIOV" == "y" ]]; then
        modify_grub "iommu" "pt"
        modify_grub "$CPU_iommu" "on"
    else
        modify_grub "iommu" "off"
        modify_grub "$CPU_iommu" "off"
    fi
}

# Function to manage screen timeout
manage_screen_timeout() {
    to_log "Configuring Screen Timeout..."
    read -p "Enter console blank timeout in seconds (default: 60): " SCREEN_TIMEOUT
    if ! [[ "$SCREEN_TIMEOUT" =~ ^[0-9]+$ ]]; then
        to_log "Invalid input. Using default 60 seconds."
        SCREEN_TIMEOUT=60
    fi
    echo "setterm -blank $SCREEN_TIMEOUT" > /etc/issue
    REBOOT_REQUIRED=1
}

# Function to enable/disable PCI passthrough modules
manage_pci_passthrough() {
    to_log "Configuring PCI Passthrough..."
    MODULES=("vfio" "vfio_iommu_type1" "vfio_pci" "vfio_virqfd")
    read -p "Enable PCI passthrough? (y/n): " ENABLE_PCI
    if [[ "$ENABLE_PCI" == "y" ]]; then
        for module in "${MODULES[@]}"; do
            if ! grep -qxF "$module" "$MODULES_FILE"; then
                echo "$module" >> "$MODULES_FILE"
            fi
        done
    else
        for module in "${MODULES[@]}"; do
            sed -i "/^$module$/d" "$MODULES_FILE"
        done
    fi
    update-initramfs -u
    REBOOT_REQUIRED=1
}

# Function to manage lid switch behavior
manage_lid_switch() {
    to_log "Configuring Lid Switch Behavior..."
    read -p "Ignore laptop lid closing? (y/n): " ENABLE_LID
    if [[ "$ENABLE_LID" == "y" ]]; then
        sed -i 's/^HandleLidSwitch=.*/HandleLidSwitch=ignore/' "$LOGIND_CONF"
        grep -q "^HandleLidSwitch=ignore" "$LOGIND_CONF" || echo "HandleLidSwitch=ignore" >> "$LOGIND_CONF"
    else
        sed -i 's/^HandleLidSwitch=ignore/#HandleLidSwitch=ignore/' "$LOGIND_CONF"
    fi
    systemctl restart systemd-logind
}

# Menu
check_root
detect_cpu

while true; do
    echo -e "\nDetected CPU: $CPU"
    echo "1) Manage IOMMU"
    echo "2) Manage ACS Override"
    echo "3) Manage SR-IOV"
    echo "4) Manage Screen Timeout"
    echo "5) Manage PCI Passthrough Modules"
    echo "6) Manage Laptop Lid Switch Behavior"
    echo "7) Apply All Settings"
    echo "8) Exit"
    read -p "Enter your choice: " CHOICE

    case "$CHOICE" in
        1) manage_iommu ;;
        2) manage_acs_override ;;
        3) manage_sriov ;;
        4) manage_screen_timeout ;;
        5) manage_pci_passthrough ;;
        6) manage_lid_switch ;;
        7) manage_iommu; manage_acs_override; manage_sriov; manage_screen_timeout; manage_pci_passthrough; manage_lid_switch ;;
        8) exit 0 ;;
        *) echo "Invalid option. Please try again." ;;
    esac
done
