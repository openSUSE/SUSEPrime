#!/bin/bash

# Script for selecting either nvidia og intel card for NVIDIA optimus laptops
# Please follow instructions given in README
# Public domain by Bo Simonsen <bo@geekworld.dk>

type=$1

pwd=`dirname $(readlink -f "$0")`
xorg_conf="$pwd/xorg.conf"
offload="$pwd/prime-offload.sh"
gpu_info=`nvidia-xconfig --query-gpu-info`
nvidia_busid=`echo "$gpu_info" |grep -i "PCI BusID"|sed 's/PCI BusID ://'|sed 's/ //g'`

case $type in
  nvidia)
      update-alternatives --set libglx.so /usr/lib64/xorg/modules/extensions/nvidia/nvidia-libglx.so

      ln -s $offload /etc/X11/xinit/xinitrc.d/prime-offload.sh

      cat $xorg_conf | sed 's/PCI:X:X:X/'${nvidia_busid}'/' > /etc/X11/xorg.conf.d/90-nvidia.conf
      cat <<< '
/usr/X11R6/lib64
/usr/X11R6/lib
      ' > /etc/ld.so.conf.d/nvidia-gfxG04.conf

      echo "Running ldconfig"
      ldconfig
  ;;
  intel)
      update-alternatives --set libglx.so /usr/lib64/xorg/modules/extensions/xorg/xorg-libglx.so
      rm -f /etc/X11/xinit/xinitrc.d/prime-offload.sh
      rm -f /etc/X11/xorg.conf.d/90-nvidia.conf
      rm -f /etc/ld.so.conf.d/nvidia-gfxG04.conf

      echo "Running ldconfig"
      ldconfig
  ;;
  *)
      echo "prime-select nvidia|intel"
      exit
  ;;
esac


