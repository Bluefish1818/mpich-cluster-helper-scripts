#!/bin/bash
# Get the hardware info of all 4 nodes
# Get the total number of processors available
hostname
processors=$(nproc)
echo "There are $processors processors"
echo "Memory information:"
free -g -h -t
echo "Disk storage information"
lsblk -d /dev/sda
