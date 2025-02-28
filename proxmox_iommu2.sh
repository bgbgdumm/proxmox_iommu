#!/bin/bash

# Define backup directory
BACKUP_BASE="/var/lib/proxmox_iommu_script_backup"
BACKUP_DIR="$BACKUP_BASE/proxmox_backup_$(date +%Y%m%d_%H%M%S)"
CONFIG_FILES=("/etc/default/grub" "/etc/modules")
BACKUP_DIRS=$(ls -d "$BACKUP_BASE/proxmox_backup_"* 2>/dev/null)

# Function to create backups
backup_configs() {
    echo "Creating backup at $BACKUP_DIR..."
    mkdir -p "$BACKUP_DIR"
    for file in "${CONFIG_FILES[@]}"; do
        cp "$file" "$BACKUP_DIR/"
    done
    echo "Backup completed!"
}

# Function to detect CPU type (Intel or AMD)
detect_cpu() {
    if grep -qi "intel" /proc/cpuinfo; then
        CPU_TYPE="intel"
    elif grep -qi "amd" /proc/cpuinfo; then
        CPU_TYPE="amd"
    else
        CPU_TYPE="unknown"
    fi
}

# Function to enable IOMMU and PCI passthrough
enable_iommu() {
    detect_cpu  # Detect the CPU type

    echo "Checking if IOMMU and PCI passthrough are already enabled..."

    # Check if IOMMU is already enabled in GRUB
    if grep -q "intel_iommu=on\|amd_iommu=on" /etc/default/grub; then
        echo "IOMMU and PCI passthrough are already enabled!"
    else
        echo "Enabling IOMMU and PCI passthrough..."

        # Set the IOMMU option based on CPU type
        if [ "$CPU_TYPE" == "intel" ]; then
            IOMMU_OPTION="intel_iommu=on"
        elif [ "$CPU_TYPE" == "amd" ]; then
            IOMMU_OPTION="amd_iommu=on"
        else
            echo "Unknown CPU type! Skipping IOMMU configuration."
            return
        fi

        # Modify GRUB to add the IOMMU option
        sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*/& $IOMMU_OPTION iommu=pt pcie_acs_override=downstream,multifunction/" /etc/default/grub

        # Update /etc/modules if necessary
        if ! grep -q "vfio" /etc/modules; then
            echo -e "vfio\nvfio_iommu_type1\nvfio_pci\nvfio_virqfd" >> /etc/modules
        fi

        # Apply changes
        update-grub
        update-initramfs -u
        echo "IOMMU & PCI passthrough enabled for $CPU_TYPE CPU! Reboot required."
    fi
}

# Function to set screen blank timeout in GRUB
set_screen_timeout() {
    # Check if consoleblank is already set in GRUB
    if grep -q "consoleblank=" /etc/default/grub; then
        echo "Screen blank timeout is already set!"
    else
        read -p "Enter timeout in minutes (default: 1): " TIMEOUT
        TIMEOUT=${TIMEOUT:-1}
        echo "Setting screen blank timeout to $TIMEOUT minute(s) in GRUB..."

        sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*/& consoleblank='$((TIMEOUT * 60))'/' /etc/default/grub

        update-grub
        echo "Screen blank timeout set! Reboot required."
    fi
}

# Function to restore from backup
restore_backup() {
    if [ -z "$BACKUP_DIRS" ]; then
        echo "No backup directories found in $BACKUP_BASE! Please create a backup first."
        return
    fi

    echo "Available backups found:"
    if [ $(echo "$BACKUP_DIRS" | wc -l) -gt 2 ]; then
        echo "Note: More than 2 backups are found. Please choose one."
    fi

    select restore_dir in $BACKUP_DIRS; do
        if [ -n "$restore_dir" ]; then
            echo "Restoring from backup: $restore_dir"
            for file in "${CONFIG_FILES[@]}"; do
                cp "$restore_dir/$(basename "$file")" "$file"
            done

            update-grub
            update-initramfs -u
            echo "Backup restored! Reboot required."
            break
        else
            echo "Invalid selection. Please choose a valid backup."
        fi
    done
}

# Main menu
while true; do
    echo -e "\n=== Proxmox PCI Passthrough Setup ==="
    echo "1) Backup current configuration"
    echo "2) Enable IOMMU & PCI passthrough"
    echo "3) Set screen blank timeout in GRUB"
    echo "4) Restore from backup"
    echo "5) Exit"
    read -p "Choose an option: " OPTION

    case $OPTION in
        1) backup_configs ;;
        2) enable_iommu ;;
        3) set_screen_timeout ;;
        4) restore_backup ;;
        5) echo "Exiting..."; exit 0 ;;
        *) echo "Invalid option, please try again." ;;
    esac
done
