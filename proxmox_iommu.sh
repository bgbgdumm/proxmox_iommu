#!/bin/bash

# Initialize global variables
REBOOT_REQUIRED=0
GRUB_FILE="/etc/default/grub"
MODULES_FILE="/etc/modules"
LOGIND_CONF="/etc/systemd/logind.conf"
BACKUP_DIR="/etc/system_tweaks_backup"
SLEEP_INTERVAL=2  # Sleep time to prevent high CPU usage

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root. Please run with sudo."
        exit 1
    fi
}

# Function to create a backup only once
backup_config() {
    mkdir -p "$BACKUP_DIR"
    for file in "$GRUB_FILE" "$MODULES_FILE" "$LOGIND_CONF"; do
        if [[ ! -f "$BACKUP_DIR/$(basename "$file").bak" ]]; then
            cp "$file" "$BACKUP_DIR/$(basename "$file").bak"
            echo "Backup created for $(basename "$file")"
        fi
    done
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
    echo "Detected CPU: $CPU"
}

# Function to safely modify GRUB parameters
modify_grub() {
    local param="$1"
    local value="$2"

    if grep -qE "\b$param=[^ ]*" "$GRUB_FILE"; then
        # Replace existing parameter
        sed -i -E "s/\b$param=[^ ]*/$param=$value/g" "$GRUB_FILE"
    else
        # Append new parameter inside the quotes
        sed -i -E "s/^(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*)\"/\1 $param=$value\"/" "$GRUB_FILE"
    fi
}

# Function to safely remove a GRUB parameter
remove_grub_param() {
    local param="$1"

    # Remove the parameter safely while ensuring no extra spaces
    sed -i -E "s/ ?\b$param=[^ ]*//g" "$GRUB_FILE"

    # Ensure no unbalanced quotes or extra spaces
    sed -i -E 's/^(GRUB_CMDLINE_LINUX_DEFAULT=") +/\1/' "$GRUB_FILE"
    sed -i -E 's/  +/ /g' "$GRUB_FILE"  # Remove excess spaces
}

# Function to update GRUB
update_grub() {
    if command -v update-grub &>/dev/null; then
        update-grub
    elif command -v grub-mkconfig &>/dev/null; then
        grub-mkconfig -o /boot/grub/grub.cfg
    else
        echo "Warning: GRUB update command not found!"
    fi
}

# Function to enable/disable IOMMU
manage_virtualization() {
    read -p "Enable Virtualization (IOMMU)? (y/n): " ENABLE_VIRT
    if [[ "$ENABLE_VIRT" == "y" ]]; then
        echo "Enabling IOMMU..."
        if [[ "$CPU" == "AMD" ]]; then
            modify_grub "amd_iommu" "on"
            modify_grub "iommu" "pt"
        else
            modify_grub "intel_iommu" "on"
            modify_grub "iommu" "pt"
        fi
    else
        echo "Disabling IOMMU..."
        remove_grub_param "amd_iommu"
        remove_grub_param "intel_iommu"
        remove_grub_param "iommu"
    fi
    update_grub
    REBOOT_REQUIRED=1
}

# Function to enable/disable screen timeout via GRUB
manage_screen_timeout() {
    read -p "Enable screen timeout via GRUB? (y/n): " ENABLE_TIMEOUT
    if [[ "$ENABLE_TIMEOUT" == "y" ]]; then
        read -p "Enter console blank timeout in seconds (default: 60): " SCREEN_TIMEOUT
        if ! [[ "$SCREEN_TIMEOUT" =~ ^[0-9]+$ ]]; then
            echo "Invalid input. Using default 60 seconds."
            SCREEN_TIMEOUT=60
        fi
        modify_grub "consoleblank" "$SCREEN_TIMEOUT"
    else
        echo "Disabling screen timeout..."
        remove_grub_param "consoleblank"
    fi
    update_grub
    REBOOT_REQUIRED=1
}

# Function to enable/disable PCI passthrough modules
manage_pci_passthrough() {
    MODULES=("vfio" "vfio_iommu_type1" "vfio_pci" "vfio_virqfd")

    read -p "Enable PCI passthrough? (y/n): " ENABLE_PCI
    if [[ "$ENABLE_PCI" == "y" ]]; then
        echo "Enabling PCI passthrough..."
        for module in "${MODULES[@]}"; do
            if ! grep -qxF "$module" "$MODULES_FILE"; then
                echo "$module" >> "$MODULES_FILE"
            fi
        done
    else
        echo "Disabling PCI passthrough..."
        for module in "${MODULES[@]}"; do
            sed -i "/^$module$/d" "$MODULES_FILE"
        done
    fi
    update-initramfs -u
}

# Function to enable/disable lid switch behavior
manage_lid_switch() {
    read -p "Ignore laptop lid closing? (y/n): " ENABLE_LID
    if [[ "$ENABLE_LID" == "y" ]]; then
        sed -i 's/^HandleLidSwitch=.*/HandleLidSwitch=ignore/' "$LOGIND_CONF"
        grep -q "^HandleLidSwitch=ignore" "$LOGIND_CONF" || echo "HandleLidSwitch=ignore" >> "$LOGIND_CONF"
    else
        sed -i 's/^HandleLidSwitch=ignore/#HandleLidSwitch=ignore/' "$LOGIND_CONF"
    fi
    systemctl restart systemd-logind
}

# Main script execution
check_root
backup_config
detect_cpu

OPTIONS=(
    "Enable/Disable Virtualization (IOMMU)"
    "Enable/Disable Screen Timeout"
    "Enable/Disable PCI Passthrough Modules"
    "Enable/Disable Laptop Lid Switch Behavior"
    "Apply All Settings"
    "Exit"
)

while true; do
    echo -e "\n===== System Configuration Menu ====="
    PS3="Enter your choice: "
    select choice in "${OPTIONS[@]}"; do
        case $REPLY in
            1) manage_virtualization ;;
            2) manage_screen_timeout ;;
            3) manage_pci_passthrough ;;
            4) manage_lid_switch ;;
            5)
                manage_virtualization
                manage_screen_timeout
                manage_pci_passthrough
                manage_lid_switch
                ;;
            6) echo "Exiting..."; exit 0 ;;
            *) echo "Invalid choice, try again." ;;
        esac
        break
    done
    sleep "$SLEEP_INTERVAL"
done

# Ask for reboot if necessary
if [[ $REBOOT_REQUIRED -eq 1 ]]; then
    read -p "A reboot is required for changes to take effect. Reboot now? (y/n): " REBOOT_NOW
    if [[ "$REBOOT_NOW" == "y" ]]; then
        echo "Rebooting now..."
        reboot
    else
        echo "Reboot later for changes to apply."
    fi
else
    echo "All changes applied successfully!"
fi
