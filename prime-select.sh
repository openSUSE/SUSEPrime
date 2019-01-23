#!/bin/bash

# Script for selecting either nvidia og intel card for NVIDIA optimus laptops
# Please follow instructions given in README

# Public domain by Bo Simonsen <bo@geekworld.dk>
# Adapted for OpenSUSE Tumbleweed by Michal Srb <msrb@suse.com>
# Augmented by bubbleguuum <bubbleguuum@free.fr>

type=$1
xorg_nvidia_conf="/etc/prime/xorg-nvidia.conf"
xorg_intel_conf_intel="/etc/prime/xorg-intel.conf"
xorg_intel_conf_intel2="/etc/prime/xorg-intel-intel.conf"
nvidia_modules="nvidia_drm nvidia_modeset nvidia_uvm nvidia"
driver_choices="nvidia|intel|intel2"
lspci_intel_line="VGA compatible controller: Intel"

function usage {
    echo
    echo "usage: `basename $0` $driver_choices|unset|get-current|apply-current"
    echo
    echo "intel: use the Intel card with the modesetting driver"
    echo "intel2: use the Intel card with the Intel open-source driver (xf86-video-intel). If you use this driver in a Plasma session, make sure to first disable vsync in the Plasma compositor settings to prevent video corruption"
    echo "nvidia: use the NVIDIA binary driver"
    echo "unset: disable effects of this script and let Xorg decide what driver to use"
    echo "get-current: display driver currently in use by this tool"
    echo "apply-current: re-apply this script using previously set driver (used by better-prime-select systemd service)"
    echo
}

function check_root {
    if (( $EUID != 0 )); then
        echo "You must run this script as root"
        exit 1
    fi
}

function clean_files {
    rm -f /etc/X11/xorg.conf.d/90-nvidia.conf
    rm -f /etc/X11/xorg.conf.d/90-intel.conf
}

case $type in
    
    apply-current)
	
        if [ -f /etc/prime/current_type ]; then
            
            current_type=`cat /etc/prime/current_type`
            
            if [ "$current_type" != "nvidia"  ] && ! lspci | grep "$lspci_intel_line" > /dev/null; then
                
                # this can happen if user set intel but changed to "Discrete only" in BIOS
                # in that case the Intel card is not visible to the system and we must switch to nvidia
                
                echo "Forcing nvidia due to Intel card not found"
                current_type="nvidia"
            fi
            
            $0 $current_type
        fi
        ;;
    
    nvidia)

	check_root
	
	if [ -f /proc/acpi/bbswitch ]; then        
            tee /proc/acpi/bbswitch > /dev/null <<EOF
ON
EOF
	fi

	# will load all other dependency modules
	modprobe nvidia_drm
        
	gpu_info=`nvidia-xconfig --query-gpu-info`
	# This may easily fail, if no NVIDIA kernel module is available or alike
	if [ $? -ne 0 ]; then
            echo "PCI BusID of NVIDIA card could not be detected!"
            exit 1
	fi
	
	# There could be more than on NVIDIA card/GPU; use the first one in that case

	nvidia_busid=`echo "$gpu_info" |grep -i "PCI BusID"|head -n 1|sed 's/PCI BusID ://'|sed 's/ //g'`

	libglx_nvidia=`update-alternatives --list libglx.so|grep nvidia-libglx.so`

	update-alternatives --set libglx.so $libglx_nvidia > /dev/null

	clean_files

	cat $xorg_nvidia_conf | sed 's/PCI:X:X:X/'${nvidia_busid}'/' > /etc/X11/xorg.conf.d/90-nvidia.conf

	echo "$type" > /etc/prime/current_type     

	$0 get-current
	;;
    
    intel|intel2)

	check_root
	
	if [ "$type" = "intel2" ]; then
            if ! rpm -q xf86-video-intel > /dev/null; then
		echo "package xf86-video-intel is not installed";
		exit 1
            fi
            
            conf=$xorg_intel_conf_intel2
	else
            # modesetting driver is part of xorg-x11-server and always available
            conf=$xorg_intel_conf_intel
	fi

	# find Intel card bus id. Without this Xorg may fail to start
	line=`lspci | grep "$lspci_intel_line" | head -1`
	if [ $? -ne 0 ]; then
            echo "Failed to find Intel card with lspci"
            exit 1
	fi

	intel_busid=`echo $line | cut -f 1 -d ' ' | sed -e 's/\./:/g;s/:/ /g' | awk -Wposix '{printf("PCI:%d:%d:%d\n","0x" $1, "0x" $2, "0x" $3 )}'`
	if [ $? -ne 0 ]; then
            echo "Failed to build Intel card bus id"
            exit 1
	fi
	
	libglx_xorg=`update-alternatives --list libglx.so|grep xorg-libglx.so`

	update-alternatives --set libglx.so $libglx_xorg > /dev/null     
	
	clean_files

	cat $conf | sed 's/PCI:X:X:X/'${intel_busid}'/' > /etc/X11/xorg.conf.d/90-intel.conf

	modprobe -r $nvidia_modules

	if [ -f /proc/acpi/bbswitch ]; then        
            tee /proc/acpi/bbswitch > /dev/null <<EOF 
OFF
EOF
            grep OFF /proc/acpi/bbswitch > /dev/null || echo "Failed to power off NVIDIA card"

	else
            rpm -q bbswitch > /dev/null || echo "bbswitch is not installed. NVIDIA card will not be powered off"
	fi
	
	echo "$type" > /etc/prime/current_type

	$0 get-current
	;;
    
    get-current)
	
	if [ -f /etc/prime/current_type ]; then
            echo -n "Driver configured: "
            cat /etc/prime/current_type
      	else
            echo "No driver configured."
            echo "Use \"`basename $0` $driver_choices\" for configuration."
	fi
	;;

    unset)

	check_root
	
	clean_files
	rm /etc/prime/current_type
	;;

    *)
	usage
	;;
esac
