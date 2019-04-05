#!/bin/bash

# Script for selecting either nvidia og intel card for NVIDIA optimus laptops
# Please follow instructions given in README

# Public domain by Bo Simonsen <bo@geekworld.dk>
# Adapted for OpenSUSE Tumbleweed by Michal Srb <msrb@suse.com>
# Extended for TUXEDO Computers by Vinzenz Vietzke <vv@tuxedocomputers.com>
# Augmented by bubbleguuum <bubbleguuum@free.fr>
# Improved by simopil <pilia.simone96@gmail.com>

type=$1
xorg_nvidia_conf="/etc/prime/xorg-nvidia.conf"
xorg_intel_conf_intel="/etc/prime/xorg-intel.conf"
xorg_intel_conf_intel2="/etc/prime/xorg-intel-intel.conf"
prime_logfile="/var/log/prime-select.log"
nvidia_modules="nvidia_drm nvidia_modeset nvidia_uvm nvidia"
driver_choices="nvidia|intel|intel2"
lspci_intel_line="VGA compatible controller: Intel"
lspci_nvidia_line="VGA compatible controller: NVIDIA"


# Check if prime-select systemd service is present (in that case service_test value is 0)
# If it is present (suse-prime-bbswitch package), the script assumes that bbswitch is to be used
# otherwise (suse-prime package) it works without bbswitch 
[ -f  /usr/lib/systemd/system/prime-select.service ]
service_test=$?   

function usage {
    echo
    echo "NVIDIA/Intel video card selection for NVIDIA Optimus laptops."
    echo
    
    if (( service_test == 0 )); then
	echo "usage: $(basename $0)           $driver_choices|unset|get-current|get-boot|log-view|log-clean"
	echo "usage: $(basename $0) boot      $driver_choices|last"
	echo "usage: $(basename $0) next-boot $driver_choices|abort"
	echo "usage: $(basename $0) service   check|disable|restore"
    else
	echo "usage: $(basename $0) $driver_choices|unset|get-current|log-view|log-clean"
    fi
    
    echo
    echo "nvidia:      use the NVIDIA proprietary driver"
    echo "intel:       use the Intel card with the \"modesetting\" driver"
    echo "intel2:      use the Intel card with the \"intel\" Open Source driver (xf86-video-intel)"
    echo "unset:       disable effects of this script and let Xorg decide what driver to use"
    echo "get-current: display driver currently configured"
    echo "log-view:    view logfile"
    echo "log-clean:   clean logfile"
    
    if (( service_test == 0 )); then
	echo "boot:        select default card at boot or set last used"
	echo "next-boot:   select card ONLY for next boot, it not touches your boot preference. abort: restores next boot to default"
	echo "get-boot:    display default card at boot"
        echo "service:     disable, check or restore prime-select service. Could be useful disabling service"
	echo "             before isolating multi-user.target to prevent service execution."
    fi
    
    #if (( service_test == 0)); then
    #    echo
    #    echo "##FOLLOWING COMMANDS ARE USED BY prime-select SERVICEs, DON'T USE THEM MANUALLY##"
    #    echo "systemd_call:       called during boot or after user logout for switch"
    #    echo "user_logout_waiter: waits user logout (used by prime-select systemd service)"
    #fi
    
    echo
}

function logging {
    if ! [ -f $prime_logfile ]; then 
        echo "##SUSEPrime logfile##" > $prime_logfile
    fi
    echo "[ $(date +"%H:%M:%S") ] ${1}" >> $prime_logfile
    echo "${1}" | systemd-cat -t suse-prime -p info
}

function check_root {
    if (( $EUID != 0 )); then
        echo "You must run this script as root"
        exit 1
    fi
}

function check_service {
    if (( service_test != 0)); then
	exit 1;
    fi	
}

function bbcheck {
    if rpm -q bbswitch > /dev/null; then
        if grep OFF /proc/acpi/bbswitch > /dev/null; then
            echo "[bbswitch] NVIDIA card is OFF"
        elif grep ON /proc/acpi/bbswitch > /dev/null; then
            echo "[bbswitch] NVIDIA card is ON"
        else
            echo "bbswitch is installed but seems broken. Cannot get NVIDIA power status"
        fi
    elif (( service_test == 0)); then
	# should never happen with suse-prime-bbswitch package as bbswitch is a dependency
        echo "bbswitch is not installed. NVIDIA card will not be powered off"
    fi
}

function clean_xorg_conf_d {
    rm -f /etc/X11/xorg.conf.d/90-nvidia.conf
    rm -f /etc/X11/xorg.conf.d/90-intel.conf
}

function set_nvidia {

    if (( service_test == 0)); then
	
    	if [ -f /proc/acpi/bbswitch ]; then        
            tee /proc/acpi/bbswitch > /dev/null <<EOF
ON
EOF
  	fi
	
    	logging "trying switch ON nvidia: $(bbcheck)"
   	
   	# will also load all necessary dependent modules
    	modprobe nvidia_drm

    fi    
    
    gpu_info=$(nvidia-xconfig --query-gpu-info)
    # This may easily fail, if no NVIDIA kernel module is available or alike
    if [ $? -ne 0 ]; then
        logging "PCI BusID of NVIDIA card could not be detected!"
        exit 1
    fi
    
    # There could be more than on NVIDIA card/GPU; use the first one in that case

    nvidia_busid=$(echo "$gpu_info" | grep -i "PCI BusID" | head -n 1 | sed 's/PCI BusID ://' | sed 's/ //g')

    libglx_nvidia=$(update-alternatives --list libglx.so|grep nvidia-libglx.so)

    update-alternatives --set libglx.so $libglx_nvidia > /dev/null

    clean_xorg_conf_d 

    cat $xorg_nvidia_conf | sed 's/PCI:X:X:X/'${nvidia_busid}'/' > /etc/X11/xorg.conf.d/90-nvidia.conf

    echo "nvidia" > /etc/prime/current_type
    logging "NVIDIA card correctly set"
}

function set_intel {
    # modesetting driver is part of xorg-x11-server and always available
    conf=$xorg_intel_conf_intel
    echo "intel" > /etc/prime/current_type
    #jump to common function intel1/intel2
    common_set_intel
}

function set_intel2 {
    conf=$xorg_intel_conf_intel2
    echo "intel2" > /etc/prime/current_type
    #jump to common function intel1/intel2
    common_set_intel
}

function common_set_intel {
    # find Intel card bus id. Without this Xorg may fail to start
    line=$(lspci | grep "$lspci_intel_line" | head -1)
    if [ $? -ne 0 ]; then
        logging "Failed to find Intel card with lspci"
        exit 1
    fi

    intel_busid=$(echo $line | cut -f 1 -d ' ' | sed -e 's/\./:/g;s/:/ /g' | awk -Wposix '{printf("PCI:%d:%d:%d\n","0x" $1, "0x" $2, "0x" $3 )}')
    if [ $? -ne 0 ]; then
        logging "Failed to build Intel card bus id"
        exit 1
    fi
    
    libglx_xorg=$(update-alternatives --list libglx.so | grep xorg-libglx.so)

    update-alternatives --set libglx.so $libglx_xorg > /dev/null     
    
    clean_xorg_conf_d

    cat $conf | sed 's/PCI:X:X:X/'${intel_busid}'/' > /etc/X11/xorg.conf.d/90-intel.conf

    if (( service_test == 0)); then

	modprobe -r $nvidia_modules

	if [ -f /proc/acpi/bbswitch ]; then        
            tee /proc/acpi/bbswitch > /dev/null <<EOF 
OFF
EOF
    	fi
	
	logging "trying switch OFF nvidia: $(bbcheck)"
	
    fi
    
    logging "Intel card correctly set"
}

function apply_current {
    if [ -f /etc/prime/current_type ]; then
        
        current_type=$(cat /etc/prime/current_type)
        
        if [ "$current_type" != "nvidia"  ] && ! lspci | grep "$lspci_intel_line" > /dev/null; then
            
            # this can happen if user set intel but changed to "Discrete only" in BIOS
            # in that case the Intel card is not visible to the system and we must switch to nvidia
            
            logging "Forcing nvidia due to Intel card not found"
            current_type="nvidia"
        elif [ "$current_type" = "nvidia" ] && ! lspci | grep "$lspci_nvidia_line" > /dev/null; then
            
            # this can happen if user set nvidia but changed to "Integrated only" in BIOS (possible on some MUXED Optimus laptops)
            # in that case the NVIDIA card is not visible to the system and we must switch to intel
            
            logging "Forcing intel due to NVIDIA card not found"
            current_type="intel"
        fi
        
        
        set_$current_type
    fi
}

function current_check {
    if [ "$(pgrep -fl "prime-select user_logout_waiter")" > /dev/null ]; then
        echo "Error: a switch operation already in execution"
        echo "You can undo it using sudo killall prime-select"
        exit 1
    fi
    if ! [ -f /etc/prime/current_type ]; then
        echo "Preparing first configuration"
    elif [ "$type" = "$(cat /etc/prime/current_type)" ]; then
        echo "$type driver already in use!"
        exit 1
    fi
}

function booting {
    if ! [ -f /etc/prime/boot_state ]; then
        echo "N" > /etc/prime/boot_state
    fi
    if ! [ -f /etc/prime/boot ]; then
        echo "last" > /etc/prime/boot
    fi
    
    if [ -f /etc/prime/forced_boot ]; then
        echo "$(cat /etc/prime/forced_boot)" > /etc/prime/current_type
        rm /etc/prime/forced_boot
        logging "Boot: forcing booting with $(cat /etc/prime/current_type), boot preference ignored"
        logging "Boot: setting-up $(cat /etc/prime/current_type) card"
        apply_current
    else
        boot_type=$(cat /etc/prime/boot)
	if [ "$boot_type" != "last" ]; then
            echo "$boot_type" > /etc/prime/current_type
        fi
        logging "Boot: setting-up $(cat /etc/prime/current_type) card"
        apply_current
    fi
}

function logout_switch {
    apply_current
    echo "N" > /etc/prime/boot_state
    logging "HotSwitch: Reaching graphical.target [ boot_state > N ]"
    systemctl isolate graphical.target &
    systemctl stop prime-select
}

case $type in
    
    nvidia|intel|intel2)
	
        current_check
        check_root
	
        if ! [ -f /var/log/prime-select.log ]; then
            echo "##SUSEPrime logfile##" > $prime_logfile
        fi

	if [ $(wc -l < $prime_logfile) -gt 1000 ]; then
            #cleaning logfile if has more than 1k events
            rm $prime_logfile &> /dev/null
            echo "##SUSEPrime logfile##" > $prime_logfile
        fi

	if [ "$type" = "intel2" ];then
            if ! rpm -q xf86-video-intel > /dev/null; then
                echo "package xf86-video-intel is not installed";
                exit 1
            fi
        fi
        
        if (( service_test == 0)); then
	    
	    if ! [ -f /etc/systemd/system/multi-user.target.wants/prime-select.service ]; then
    		echo "ERROR: prime-select service seems broken or disabled by user. Try prime-select service restore"
        	exit 1
       	    fi
       	    
       	    if ! { [ "$(bbcheck)" = "[bbswitch] NVIDIA card is ON" ] || [ "$(bbcheck)" = "[bbswitch] NVIDIA card is OFF" ]; }; then
    	        bbcheck
            fi
            
	    #DM_check
	    runlev=$(runlevel | awk '{print $2}')
	    if [ $runlev = 5 ]; then
		#GDM_mode
		if [ "$(systemctl status display-manager | grep gdm)" > /dev/null ]; then
		    $0 user_logout_waiter $type gdm &
		    logging "user_logout_waiter: started"
		    #SDDM_mode
		elif [ "$(systemctl status display-manager | grep sddm)" > /dev/null ]; then
		    $0 user_logout_waiter $type sddm &
		    logging "user_logout_waiter: started"
		    #lightdm_mode
		elif [ "$(systemctl status display-manager | grep lightdm)" > /dev/null ]; then
		    $0 user_logout_waiter $type lightdm &
		    logging "user_logout_waiter: started"
		    #XDM_mode
		elif [ "$(systemctl status display-manager | grep xdm)" > /dev/null ]; then
		    $0 user_logout_waiter $type xdm &
		    logging "user_logout_waiter: started"
		    #KDM_mode(uses xdm->calls xdm_mode)
		elif [ "$(systemctl status display-manager | grep kdm)" > /dev/null ]; then
		    $0 user_logout_waiter $type xdm &
		    logging "user_logout_waiter: started"
		    #unsupported_dm_force_close_option
		else
		    echo "Unsupported display-manager, please report this to project page to add support."
		    echo "Script works even in init 3"
		    echo "You can force-close session and switch graphics [could be dangerous],"
		    read -p "ALL UNSAVED DATA IN SESSION WILL BE LOST, CONTINUE? [Y/N]: " choice 
		    case "$choice" in
			y|Y ) 
			    killall xinit 
			    $0 user_logout_waiter $type now
			    ;;
			* ) echo "Aborted. Exit."; exit ;;
		    esac
		fi    
		#manually_started_X_case
	    elif [ $runlev = 3 ] && [ "$(pgrep -fl "xinit")" > /dev/null ]; then
		$0 user_logout_waiter $type x_only &
		logging "user_logout_waiter: started"
	    else
		echo "Seems you are on runlevel 3."
		read -p "Do you want to switch graphics now and reach graphical.target? [y/n]: " choice
		case "$choice" in
		    y|Y ) $0 user_logout_waiter $type now ;;
		    * ) echo "Aborted. Exit."; exit ;;
		esac
	    fi

	else  # no service used

	    echo $type > /etc/prime/current_type
	    apply_current

	fi
	
	echo -e "Logout to switch graphics"
	;;
    
    boot)

	check_service
        check_root
	
	case $2 in
	    
            nvidia|intel|intel2|last)
		
                if [ "$2" = "intel2" ]; then  
                    if ! rpm -q xf86-video-intel > /dev/null; then
                        echo "package xf86-video-intel is not installed";
                        exit 1
                    fi
                fi
	        echo "$2" > /etc/prime/boot
                $0 get-boot
	        ;;
	    
	    *)
		
                echo "Invalid choice"
                usage
	        ;;
        esac
	;;
    
    next-boot)

	check_service
        check_root
	
        case $2 in
	    
            nvidia|intel|intel2)
                
                if [ "$2" = "intel2" ]; then  
                    if ! rpm -q xf86-video-intel > /dev/null; then
                        echo "package xf86-video-intel is not installed";
                        exit 1
                    fi
                fi
                echo "$2" > /etc/prime/forced_boot
                $0 get-boot
	        ;;
	    
	    abort)
	        
                if [ -f /etc/prime/forced_boot ]; then
                    rm /etc/prime/forced_boot
                    echo "Next boot forcing aborted"
                else
                    echo "Next boot is NOT forced"
                    exit 1
                fi
	        ;;

            *)
		
                echo "Invalid choice"
                usage
	        ;;
        esac
	;;
    
    
    get-current)
	
	if [ -f /etc/prime/current_type ]; then
            echo -n "Driver configured: "
            cat /etc/prime/current_type
      	else
            echo "No driver configured."
            usage
	fi
	
        bbcheck
	;; 

    unset)

	check_root
	$0 service disable
	clean_xorg_conf_d
	rm /etc/prime/current_type &> /dev/null
	rm /etc/prime/boot_state &> /dev/null
	rm /etc/prime/boot &> /dev/null
	rm /etc/prime/forced_boot &> /dev/null
	rm $prime_logfile &> /dev/null
	;;
    
    service)

	check_service
	
        case $2 in
	    
	    check)
		
                if [ -f /etc/systemd/system/multi-user.target.wants/prime-select.service ]; then
		    echo "prime-select: service is set correctly"
		    exit
                fi
                echo "prime-select: service has a wrong setting or is disabled by user, please do prime-select service restore"
                echo "If you are running this command in multi-user.target please ignore this message"
		;;
	    
	    restore)
		
                check_root
                systemctl enable prime-select
                echo "prime-select: service restored"
                logging "service restored by user"
		;;
	    
	    disable)
                
                check_root
                systemctl disable prime-select
                echo -e "prime-select: service disabled. Remember prime-select needs this service to work correctly.\nUse prime-select service restore to enable service again "
                logging "service disabled by user"
		;;
	    
	    *)
		
                echo "Invalid choice"
                usage
	        ;;
        esac
        
	
	;;

    user_logout_waiter)
        
        currtime=$(date +"%T");
        #manage journalctl to check when X restarted, then jump init 3
        case "$3" in
            
            gdm )
		#GDM_mode
		until [ "$(journalctl --since "$currtime" | grep "pam_unix(gdm-password:session): session closed")" > /dev/null ]; do
                    sleep 0.5s
		done
		logging "user_logout_waiter: X restart detected, preparing switch to $2 [ boot_state > S ]"
		;;    
            
            #SDDM_mode
            sddm )
		until [ "$(journalctl --since "$currtime" -e _COMM=sddm | grep "Removing display")" > /dev/null ]; do
                    sleep 0.5s
		done
		logging "user_logout_waiter: X restart detected, preparing switch to $2 [ boot_state > S ]"
		;;
            
            #lightdm_mode
            lightdm  )
		until [ "$(journalctl --since "$currtime" -e | grep "pam_unix(lightdm:session): session closed")" > /dev/null ]; do
                    sleep 0.5s
		done
		logging "user_logout_waiter: X restart detected, preparing switch to $2 [ boot_state > S ]"
		;;
            
            #xdm/kdm_mode
            xdm )
		until [ "$(journalctl --since "$currtime" -e | grep "pam_unix(xdm:session): session closed for user")" > /dev/null ]; do
                    sleep 0.5s
		done
		logging "user_logout_waiter: X restart detected, preparing switch to $2 [ boot_state > S ]"
		#stopping display-manager before runlev.3 seems work faster
		systemctl stop display-manager
		;;
            
            #manually_started_X_case
            x_only )
		while [ "$(pgrep -fl "xinit")" > /dev/null ]; do
                    sleep 0.5s
		done
		logging "user_logout_waiter: X stop detected, preparing switch to $2 [ boot_state > S ]"
		;;
            now )
		logging "user_logout_waiter: runlevel 3 mode, preparing switch to $2 [ boot_state > S ]"
		;;
        esac
        
        echo $2 > /etc/prime/current_type
        echo "S" > /etc/prime/boot_state
        logging "HotSwitch: Reaching multi-user.target"
        systemctl isolate multi-user.target
	;;
    
    systemd_call)

        #checks if system is booting or switching only
        if [ "$(journalctl -b 0 | grep suse-prime)" > /dev/null ]; then
            if [ "$(cat /etc/prime/boot_state)" = "S" ]; then
                logout_switch
            fi
        else
            booting
        fi
	;;
    
    get-boot)

	check_service
	
        if [ -f /etc/prime/boot ]; then
	    echo "Default at system boot: $(cat /etc/prime/boot)"
        else
	    echo "Default at system boot: auto (last)"
	    echo "You can configure it with prime-select boot intel|intel2|nvidia|last"
        fi
        if [ -f /etc/prime/forced_boot ]; then
	    echo "Next boot forced to $(cat /etc/prime/forced_boot) by user"
        fi

	;;
    
    log-view)
	
        if [ -f $prime_logfile ]; then
            less +G -e $prime_logfile
        else
            echo "No logfile in /var/log/prime-select.log"
        fi
	;;
    
    log-clean)
	
        if [ -f $prime_logfile ]; then
            check_root
	    rm $prime_logfile
	    echo "$prime_logfile removed!"
	else
	    echo "$prime_logfile is already clean!"
        fi
	;;
    
    *)
        usage
	;;
esac
