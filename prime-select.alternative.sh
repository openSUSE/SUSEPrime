#!/bin/bash

# Script for selecting either nvidia og intel card for NVIDIA optimus laptops
# Please follow instructions given in README

# Public domain by Bo Simonsen <bo@geekworld.dk>

type=$1

xorg_conf="/etc/prime/xorg.conf"
offload="/etc/prime/prime-offload.sh"

# nvidia tools need different library path
export LD_LIBRARY_PATH=/usr/lib64/nvidia/

function clean_files {
      rm -f /etc/X11/xinit/xinitrc.d/prime-offload.sh
      rm -f /etc/X11/xorg.conf.d/90-nvidia.conf
      rm -f /etc/ld.so.conf.d/nvidia-libs.conf 

      # Initial file provided by nvidia libs
      rm -f /etc/ld.so.conf.d/nvidia-gfxG0*.conf   
}

case $type in
  nvidia)
      clean_files 

      gpu_info=`nvidia-xconfig --query-gpu-info`
      nvidia_busid=`echo "$gpu_info" |grep -i "PCI BusID"|sed 's/PCI BusID ://'|sed 's/ //g'`

      ln -s $offload /etc/X11/xinit/xinitrc.d/prime-offload.sh

      cat $xorg_conf | sed 's/PCI:X:X:X/'${nvidia_busid}'/' > /etc/X11/xorg.conf.d/90-nvidia.conf

      echo "/usr/lib64/nvidia" > /etc/ld.so.conf.d/nvidia-libs.conf
      echo "/usr/lib64/nvidia/tls" >> /etc/ld.so.conf.d/nvidia-libs.conf
      echo "/usr/lib64/nvidia/vdpau" >> /etc/ld.so.conf.d/nvidia-libs.conf

      echo "/usr/lib/nvidia" >> /etc/ld.so.conf.d/nvidia-libs.conf

      echo "Running ldconfig"

      ldconfig
  ;;
  intel)
      clean_files

      echo "Running ldconfig"

      ldconfig
  ;;
  *)
      echo "prime-select nvidia|intel"
      exit
  ;;
esac
