#!/bin/bash
# Automated setup for VirtualBox VM nodes for hardware isolation
# VBoxManage is the primary command used to work with VirtualBox, and always requires a subcommand to work.
# For use in Oracle VirtualBox Command Line Management Interface Version 7.2.6_Ubuntu

# Enable strict mode for scripting, disallows unknown behaviors
set -euo pipefail

if [[ "$EUID" -eq 0 ]]; then
    echo "Error: Do not run this script with sudo."
    echo "Run it as user mpiu:"
    echo "  ./VBoxManageInitialSetup.sh"
    exit 1
fi

# Get hostname number and store in variable
hostnum=$(hostname | grep -oE '[0-9]+' | tail -n 1 || true)

# If getting the host number fails, exit the program before any problems start
if [[ -z "$hostnum" ]]; then echo "Error: No number was found in hostname: $(hostname)"; exit 1; fi

# Create virtual machine name
vmName="vb${hostnum}"

echo "Hostname: $(hostname)"
echo "VM name: $vmName"

# If the Ubuntu Server iso cannot be found, exit the program
iso="/mirror/mpiu/ubuntu-26.04-live-server-amd64.iso"
if [[ ! -f "$iso" ]]; then echo "Error: ISO does not exist"; echo "$iso"; exit 1; fi

# The VirtualBox default directory of $HOME/VirtualBox\ VMs won't work because the home directory is mounted as the same folder as /mirror/mpiu
# In order to have proper isolation, the virtual machine has to be stored locally, so make a new directory as shown below
# This will work since we are running the the script as sudo via ssh
vmBase="/VirtualBox_VMs"
vmConfig="/VirtualBox_Config"

# Create local VirtualBox configuration directory
# sudo mkdir -p "$vmConfig"
# sudo chown -R mpiu:mpiu "$vmConfig"
# sudo chmod 700 "$vmConfig"
# sudo install method below is safer
sudo install -d -o mpiu -g mpiu -m 700 "$vmConfig"
export VBOX_USER_HOME="$vmConfig"
echo "$VBOX_USER_HOME"

# Create local VirtualBox VM storage directory
# sudo mkdir -p "$vmBase"
# sudo chown -R mpiu:mpiu "$vmBase"
# sudo install method below is safer
sudo install -d -o mpiu -g mpiu -m 755 "$vmBase"

# Exit the program if vmBase cannot be found
if [[ ! -d "$vmBase" ]]; then echo "Error: Failed to create $vmBase"; exit 1; fi
# Exit the program if vmBase cannot be found
if [[ ! -d "$vmConfig" ]]; then echo "Error: Failed to create $vmConfig"; exit 1; fi

vboxEnv="export VBOX_USER_HOME=$vmConfig"

if ! grep -qxF "$vboxEnv" /mirror/mpiu/.profile 2>/dev/null; then
        echo "$vboxEnv" >> /mirror/mpiu/.profile
fi

if ! grep -qxF "$vboxEnv" /mirror/mpiu/.bashrc 2>/dev/null; then
        echo "$vboxEnv" >> /mirror/mpiu/.bashrc
fi

VBoxManage setproperty machinefolder "$vmBase"
echo "Showing existing vms list and default machine folder:"
VBoxManage list vms
VBoxManage list systemproperties | grep "Default machine folder"


# createvm allows you to create a new virtual machine given certan parameters.
# For more info, visit https://www.virtualbox.org/manual/ch08.html#vboxmanage-createvm

# Verify that the virtual machine is not already created so that there are no overwrites
vmFile="$vmBase/$vmName/$vmName.vbox"
if VBoxManage showvminfo "$vmName" >/dev/null 2>&1; then

        echo "Notice: Virtual machine $vmName already exists and is registered."
        echo "Createvm process skipped, checking vm configuration."

elif [[ -f "$vmFile" ]]; then

        echo "Existing $vmFile found."
        echo "Registering $vmName..."
        VBoxManage registervm "$vmFile"

else
        # Create the virtual machine with vbN as the name, and store in the local VirtualBox_VMs folder.
        VBoxManage createvm --name "$vmName" --ostype "Ubuntu_64" --basefolder "$vmBase" --platform-architecture=x86 --register
fi

# Ensure that the VM is off before conducting any of the below modifications.
vmState=$( VBoxManage showvminfo "$vmName" --machinereadable | sed -n 's/^VMState="\(.*\)"/\1/p')

echo "VM state: $vmState"

if [[ "$vmState" != "poweroff" && "$vmState" != "aborted" ]]; then
    echo "Error: $vmName is currently in state: $vmState"
    echo "The VM must be powered off before its hardware configuration is changed."
    exit 1
fi

# Set initial operating system and password, use the mirror password of vbpass1
# VBoxManage createvm --name "$vmName" --ostype "Ubuntu_64" --password /mirror/mpiu/vbPass --register --basefolder /VirtualBox_VMs
# The above line is wrong, the --password flag is used for encrypting the entire VM, not to set the user login password

# Set the cpu, memory, and vram allocations
VBoxManage modifyvm "$vmName" --cpus 4 --memory 4096 --vram 128 --ioapic on

# Enable graphics controllers and mouse options
VBoxManage modifyvm "$vmName" --graphicscontroller vmsvga --usb-ohci=on --mouse usbtablet


# Create host-only networking interface for virtual machines
hostOnlyIf="vboxnet0"
if ! VBoxManage list hostonlyifs | grep -E "^Name:[[:space:]]+$hostOnlyIf$" >/dev/null; then
        echo "$hostOnlyIf does not exist. Creating the interface..."
        VBoxManage hostonlyif create
else
        echo "$hostOnlyIf already exists, skipping host-only interface creation process."
fi

# Verify that VirtualBox actually created vboxnet0
if ! VBoxManage list hostonlyifs | grep -E "^Name:[[:space:]]+$hostOnlyIf$" >/dev/null; then
        echo "ERROR: $hostOnlyIf still does not exist."
        echo
        echo "Available VirtualBox host-only interfaces:"
        VBoxManage list hostonlyifs
        exit 1
fi

echo "Configuring $hostOnlyIf as 192.168.56.1/24"
VBoxManage hostonlyif ipconfig vboxnet0 --ip 192.168.56.1 --netmask 255.255.255.0
ip addr show "$hostOnlyIf"

# Set network adapters to match test virtual machine cluster for easier configuration
# Network adapter 1 is the host-only connection, which allows for local communication, host only adapter is set to vboxnet0
# Network adapter 2 is the NAT, which allows for downloads and updates from the wider internet
VBoxManage modifyvm "$vmName" --nic1 hostonly --host-only-adapter1 vboxnet0 --nic2 nat

vmDisk="$vmBase/Ubuntu_64_$vmName.vdi"
diskCreated=0
# Create hard disk locally on each node, not the mirror mount. Allocated size is roughly 25GiB
if [[ ! -f "$vmDisk" ]]; then
        echo
        echo "Virtual disk for $vmName not found, creating disk."
        VBoxManage createmedium disk --filename "$vmDisk" --size 25000 --variant Standard
        diskCreated=1
else
        echo
        echo "Virtual disk for $vmName already exists, skipping disk creation process"
fi

# Check if an existing SATA controller exists for $vmName
if VBoxManage showvminfo "$vmName" --machinereadable | grep -E '^storagecontrollername[0-9]+="SATA Controller"$' >/dev/null; then
        echo
        echo "SATA Controller already exists, skipping process."
else
        echo
        echo "Creating SATA Controller..."
        # Create SATA controller and attach the virtual disk
        VBoxManage storagectl "$vmName" --name "SATA Controller" --add sata --controller IntelAhci
fi
VBoxManage storageattach "$vmName" --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium "$vmBase/Ubuntu_64_$vmName.vdi"

# Check if an existing IDE controller exists for $vmName
if VBoxManage showvminfo "$vmName" --machinereadable | grep -E '^storagecontrollername[0-9]+="IDE Controller"$' >/dev/null; then
        echo
        echo "IDE Controller already exists, skipping process."
else
        echo
        echo "Creating IDE Controller"
        # Create IDE controller and attach the DVD drive so that the ubuntu server iso can be mounted and be used to reinstall the OS
        VBoxManage storagectl "$vmName" --name "IDE Controller" --add ide --controller PIIX4
fi
VBoxManage storageattach "$vmName" --storagectl "IDE Controller" --port 1 --device 0 --type dvddrive --medium "$iso"

# Configure the VM such that the iso is booted into first upon first encounter
if [[ "$diskCreated" -eq 1 ]]; then
        echo "New disk detected. Setting boot configuration to Ubuntu Server installation DVD first."
        VBoxManage modifyvm "$vmName" --boot1 dvd --boot2 disk --boot3 none --boot4 none
else
        echo "Existing disk detected. Booting from hard disk first."
        # VBoxManage modifyvm "$vmName" --boot1 disk --boot2 dvd --boot3 none --boot4 none
fi

# Default installer resolution is 800x600, which looks small on most screens
VBoxManage setextradata "$vmName" GUI/ScaleFactor 1.5

# Enable Remote Desktop options on port 10001 for ease of administration
VBoxManage modifyvm "$vmName" --vrde=on
VBoxManage modifyvm "$vmName" --vrde-multi-con=on --vrde-port=10001

# Make sure that VDRE is set to the correct port
# VBoxManage showvminfo "$vmName" | grep -i -A8 vrde
# ss -ltn | grep ':10001'

# Verify the Virtual Machine after everything has been set up
# VBoxManage startvm "$vmName" --type headless
# VBoxManage showvminfo "$vmName"

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
