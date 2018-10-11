#!/bin/bash

# Script for selecting either nvidia og intel card for NVIDIA optimus laptops
# Please follow instructions given in README

# Public domain by Bo Simonsen <bo@geekworld.dk>
# Adapted for OpenSUSE Tumbleweed by Michal Srb <msrb@suse.com>

type=$1

xorg_nvidia_conf="/etc/prime/xorg-nvidia.conf"
xorg_intel_conf="/etc/prime/xorg-intel.conf"

function clean_files {
      rm -f /etc/X11/xorg.conf.d/90-nvidia.conf
      rm -f /etc/X11/xorg.conf.d/90-intel.conf
}

case $type in
  nvidia)
      clean_files 

      gpu_info=`nvidia-xconfig --query-gpu-info`
      nvidia_busid=`echo "$gpu_info" |grep -i "PCI BusID"|sed 's/PCI BusID ://'|sed 's/ //g'`
      libglx_nvidia=`update-alternatives --list libglx.so|grep nvidia-libglx.so`

      update-alternatives --set libglx.so $libglx_nvidia

      cat $xorg_nvidia_conf | sed 's/PCI:X:X:X/'${nvidia_busid}'/' > /etc/X11/xorg.conf.d/90-nvidia.conf
  ;;
  intel)
      clean_files

      libglx_xorg=`update-alternatives --list libglx.so|grep xorg-libglx.so`

      update-alternatives --set libglx.so $libglx_xorg

      cp $xorg_intel_conf /etc/X11/xorg.conf.d/90-intel.conf
  ;;
  *)
      echo "prime-select nvidia|intel"
      exit
  ;;
esac
