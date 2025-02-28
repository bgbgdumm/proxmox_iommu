#!/bin/bash

# Initialize global variables
REBOOT_REQUIRED=0

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
    echo "Detected CPU: $CPU"
}

# Function to enable or disable virtualization (IOMMU) and screen timeout
manage_virtualization() {
    read -p "Do you want to enable virtualization and screen timeout? (y/n): " ENABLE_VIRT
    if [[ "$ENABLE_VIRT" == "y" ]]; then
        read -p "Enter screen turnoff time in seconds (default: 60): " SCREEN_TIMEOUT
        SCREEN_TIMEOUT=${SCREEN_TIMEOUT:-60}

        if [[ "$CPU" == "AMD" ]]; then
            echo "Enabling AMD IOMMU..."
            sed -i 's/\bamd_iommu=on\b//g; s/\biommu=pt\b//g' /etc/default/grub
            sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT/ s/"$/ amd_iommu=on iommu=pt consoleblank='"$SCREEN_TIMEOUT"'"/' /etc/default/grub
        else
            echo "Enabling Intel IOMMU..."
            sed -i 's/\bintel_iommu=on\b//g; s/\biommu=pt\b//g' /etc/default/grub
            sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT/ s/"$/ intel_iommu=on iommu=pt consoleblank='"$SCREEN_TIMEOUT"'"/' /etc/default/grub
        fi

        update-grub
        echo "Setting screen timeout to $SCREEN_TIMEOUT seconds..."
        setterm -blank "$((SCREEN_TIMEOUT / 60))"
        REBOOT_REQUIRED=1
    else
        echo "Disabling IOMMU..."
        sed -i 's/\bamd_iommu=on\b//g; s/\biommu=pt\b//g' /etc/default/grub
        sed -i 's/\bintel_iommu=on\b//g; s/\biommu=pt\b//g' /etc/default/grub
        update-grub
        REBOOT_REQUIRED=1
    fi
}

# Function to manage PCI passthrough modules
manage_pci_passthrough() {
    MODULES_FILE="/etc/modules"
    MODULES=("vfio" "vfio_iommu_type1" "vfio_pci" "vfio_virqfd")

    read -p "Enable PCI passthrough? (y/n): " ENABLE_PCI
    if [[ "$ENABLE_PCI" == "y" ]]; then
        echo "Enabling PCI passthrough..."
        for module in "${MODULES[@]}"; do
            modprobe "$module"
            grep -qxF "$module" "$MODULES_FILE" || echo "$module" >> "$MODULES_FILE"
        done
        echo "PCI passthrough enabled."
    else
        echo "Disabling PCI passthrough..."
        for module in "${MODULES[@]}"; do
            if lsmod | grep -q "$module"; then
                modprobe -r "$module"
            fi
            sed -i "/^$module$/d" "$MODULES_FILE"
        done
        echo "PCI passthrough disabled."
    fi
}

# Function to manage lid switch behavior
manage_lid_switch() {
    LOGIND_CONF="/etc/systemd/logind.conf"

    read -p "Ignore laptop lid closing? (y/n): " ENABLE_LID
    if [[ "$ENABLE_LID" == "y" ]]; then
        sed -i 's/^HandleLidSwitch=.*/HandleLidSwitch=ignore/' "$LOGIND_CONF"
        if ! grep -q "^HandleLidSwitch=ignore" "$LOGIND_CONF"; then
            echo "HandleLidSwitch=ignore" >> "$LOGIND_CONF"
        fi
        systemctl restart systemd-logind
        echo "Lid switch ignored."
    else
        sed -i 's/^HandleLidSwitch=ignore/#HandleLidSwitch=ignore/' "$LOGIND_CONF"
        systemctl restart systemd-logind
        echo "Restored default lid switch behavior."
    fi
}

# Menu
check_root
detect_cpu

echo "Choose an option:"
echo "1) Manage Virtualization & Screen Timeout"
echo "2) Manage PCI Passthrough Modules"
echo "3) Manage Laptop Lid Switch Behavior"
echo "4) Apply All Settings"
echo "5) Exit"

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
    5) echo "Exiting..."; exit 0 ;;
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
