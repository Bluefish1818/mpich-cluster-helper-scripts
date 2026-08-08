#!/bin/bash
# Initial setup for nodes to locally store VirtualBox VMs and Registry files
# Get hostname number and store in variable
set -euo pipefail
hostnum=$(hostname | grep -oE '[0-9]+' | tail -n 1 || true)

if [[ "$EUID" -eq 0 ]]; then
    echo "Error: Do not run this script with sudo."
    echo "Run it as user mpiu:"
    echo "  ./VBoxManageInitialSetup.sh"
    exit 1
fi

# If getting the host number fails, exit the program before any problems start
if [[ -z "$hostnum" ]]; then echo "Error: No number was found in hostname: $(hostname)"; exit 1; fi
# Create virtual machine name
vmName="vb${hostnum}"

echo "Hostname: $(hostname)"
echo "VM name:  $vmName"

sudo mkdir -p /VirtualBox_Config
sudo chown -R mpiu:mpiu /VirtualBox_Config
sudo chmod 700 /VirtualBox_Config
export VBOX_USER_HOME=/VirtualBox_Config
echo "$VBOX_USER_HOME"

sudo mkdir -p /VirtualBox_VMs
sudo chown -R mpiu:mpiu /VirtualBox_VMs

if ! grep -qxf 'export VBOX_USER_HOME=/VirtualBox_Config' /mirror/mpiu/.profile 2>/dev/null; then
        echo 'export VBOX_USER_HOME=/VirtualBox_Config' >> /mirror/mpiu/.profile
fi

if ! grep -qxf 'export VBOX_USER_HOME=/VirtualBox_Config' /mirror/mpiu/.bashrc 2>/dev/null; then
        echo 'export VBOX_USER_HOME=/VirtualBox_Config' >> /mirror/mpiu/.bashrc
fi

VBoxManage setproperty machinefolder /VirtualBox_VMs
echo "Showing existing vms list and default machine folder:"
VBoxManage list vms
VBoxManage list systemproperties | grep "Default machine folder"

# --------------------------------------------------
# Register an existing local VM ONLY if one exists
# --------------------------------------------------

vmFile="/VirtualBox_VMs/$vmName/$vmName.vbox"

if VBoxManage showvminfo "$vmName" >/dev/null 2>&1; then

    echo
    echo "VM $vmName is already registered."
    echo "Skipping registration."

elif [[ -f "$vmFile" ]]; then

    echo
    echo "Existing VM configuration found:"
    echo "$vmFile"
    echo "Registering $vmName..."

    VBoxManage registervm "$vmFile"

else

    echo
    echo "No existing VM configuration found for $vmName."
    echo "Nothing needs to be registered."
    echo "The VM can now be created by VBoxManageCluster.sh."

fi

echo
echo "Registered VMs:"
VBoxManage list vms

echo
echo "Directory ownership:"
ls -ld /VirtualBox_Config /VirtualBox_VMs

echo
echo "VirtualBox registry files:"
ls -la /VirtualBox_Config

echo
echo "Initial VirtualBox setup complete."
