#!/bin/bash

# Define backup directory
BACKUP_DIR="/root/proxmox_backup_$(date +%F_%T)"
CONFIG_FILES=("/etc/default/grub" "/etc/modules" "/etc/pve/qemu-server/")
RESTORE_DIR=$(ls -d /root/proxmox_backup_* 2>/dev/null | tail -n1)

# Function to create backups
backup_configs() {
    echo "Creating backup at $BACKUP_DIR..."
    mkdir -p "$BACKUP_DIR"
    for file in "${CONFIG_FILES[@]}"; do
        cp -r "$file" "$BACKUP_DIR/"
    done
    echo "Backup completed!"
}

# Function to enable IOMMU and PCI passthrough
enable_iommu() {
    echo "Enabling IOMMU and PCI passthrough..."
    
    # Modify GRUB
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*/& intel_iommu=on amd_iommu=on iommu=pt pcie_acs_override=downstream,multifunction/' /etc/default/grub

    # Update /etc/modules
    echo -e "vfio\nvfio_iommu_type1\nvfio_pci\nvfio_virqfd" >> /etc/modules

    # Apply changes
    update-grub
    update-initramfs -u
    echo "IOMMU & PCI passthrough enabled! Reboot required."
}

# Function to set screen blank timeout in GRUB
set_screen_timeout() {
    read -p "Enter timeout in minutes (default: 1): " TIMEOUT
    TIMEOUT=${TIMEOUT:-1}
    echo "Setting screen blank timeout to $TIMEOUT minute(s) in GRUB..."

    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*/& consoleblank='$((TIMEOUT * 60))'/' /etc/default/grub

    update-grub
    echo "Screen blank timeout set! Reboot required."
}

# Function to restore from backup
restore_backup() {
    if [ -z "$RESTORE_DIR" ]; then
        echo "No backup found!"
        return
    fi

    echo "Restoring from backup: $RESTORE_DIR"
    for file in "${CONFIG_FILES[@]}"; do
        cp -r "$RESTORE_DIR/$(basename "$file")" "$file"
    done

    update-grub
    update-initramfs -u
    echo "Backup restored! Reboot required."
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
