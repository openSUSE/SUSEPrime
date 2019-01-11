#!/bin/bash

# Script for selecting either nvidia og intel card for NVIDIA optimus laptops
# Please follow instructions given in README

# Public domain by Bo Simonsen <bo@geekworld.dk>
# Adapted for OpenSUSE Tumbleweed by Michal Srb <msrb@suse.com>
# Extended for TUXEDO Computers by Vinzenz Vietzke <vv@tuxedocomputers.com>

type=$1

xorg_nvidia_conf="/etc/prime/xorg-nvidia.conf"
xorg_intel_conf="/etc/prime/xorg-intel.conf"

function clean_files {
      rm -f /etc/X11/xorg.conf.d/90-nvidia.conf
      rm -f /etc/X11/xorg.conf.d/90-intel.conf
}

case $type in
  nvidia)
      if [[ $EUID -ne 0 ]]; then
         echo "This script must be run with root permissions" 2>&1
         exit 1
      fi

      clean_files 

      gpu_info=`nvidia-xconfig --query-gpu-info`
      # This may easily fail, if no NVIDIA kernel module is available or alike
      if [ $? -ne 0 ]; then
         echo "PCI BusID of NVIDIA card could not be detected!"
         exit 1
      fi
      # There could be more than on NVIDIA card/GPU; use the first one in that case
      nvidia_busid=`echo "$gpu_info" |grep -i "PCI BusID"|head -n 1|sed 's/PCI BusID ://'|sed 's/ //g'`
      libglx_nvidia=`update-alternatives --list libglx.so|grep nvidia-libglx.so`

      update-alternatives --set libglx.so $libglx_nvidia

      cat $xorg_nvidia_conf | sed 's/PCI:X:X:X/'${nvidia_busid}'/' > /etc/X11/xorg.conf.d/90-nvidia.conf
      echo "nvidia" > /etc/prime/current_type
  ;;
  intel)
      if [[ $EUID -ne 0 ]]; then
         echo "This script must be run with root permissions" 2>&1
         exit 1
      fi

      clean_files

      libglx_xorg=`update-alternatives --list libglx.so|grep xorg-libglx.so`

      update-alternatives --set libglx.so $libglx_xorg

      cp $xorg_intel_conf /etc/X11/xorg.conf.d/90-intel.conf
      echo "intel" > /etc/prime/current_type
  ;;
  query)
      if [ -f /etc/prime/current_type ]; then
         echo -n "Currently running: "
         cat /etc/prime/current_type
      else
         echo -n "Not configured yet! "
         echo "Please use \"prime-select nvidia|intel\" for configuration."
      fi
  ;;
  *)
      echo "Usage: prime-select nvidia|intel|query"
      exit
  ;;
esac
