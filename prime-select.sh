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
xorg_nvidia_prime_render_offload="/etc/prime/xorg-nvidia-prime-render-offload.conf"
prime_logfile="/var/log/prime-select.log"
nvidia_modules="nvidia_drm nvidia_modeset nvidia_uvm nvidia"
driver_choices="nvidia|intel|intel2"
lspci_intel_line="VGA compatible controller: Intel"
lspci_nvidia_vga_line="VGA compatible controller: NVIDIA"
lspci_nvidia_3d_line="3D controller: NVIDIA"

# name of the laptop panel output as returned by 'xrandr -q'. Driver dependent, because why not
ls /sys/class/drm/ | grep -q LVDS
if [ $? -eq 0 ]; then
    panel_nvidia=LVDS-1-1
    panel_intel=LVDS-1
    panel_intel2=LVDS1
else
    panel_nvidia=eDP-1-1
    panel_intel=eDP-1
    panel_intel2=eDP1
fi

# Check if prime-select service is enabled. Some users may want to use nvidia prime offloading sometimes so they can disable service temporarily.
# SusePRIME bbswitch will work as non-bbswitch one
[ -f /etc/systemd/system/multi-user.target.wants/prime-select.service ]
service_test=$?   

# Check if prime-select systemd service is present (in that case service_test value is 0)
# If it is present (suse-prime-bbswitch package), the script assumes that bbswitch is to be used
# otherwise (suse-prime package) it works without bbswitch 
[ -f /usr/lib/systemd/system/prime-select.service ]
service_test_installed=$?

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
    echo "             PRIME Render Offload possible with >= 435.xx NVIDIA driver with prime-select service DISABLED"
    echo "intel2:      use the Intel card with the \"intel\" Open Source driver (xf86-video-intel)"
    echo "             PRIME Render Offload possible with >= 435.xx NVIDIA driver with prime-select service DISABLED"
    echo "unset:       disable effects of this script and let Xorg decide what driver to use"
    echo "get-current: display driver currently configured"
    echo "log-view:    view logfile"
    echo "log-clean:   clean logfile"
    
    if (( service_test_installed == 0 )); then
	echo "boot:        select default card at boot or set last used"
	echo "next-boot:   select card ONLY for next boot, it not touches your boot preference. abort: restores next boot to default"
	echo "get-boot:    display default card at boot"
    echo "service:     disable, check or restore prime-select service."
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
        if (( service_test_installed != 0)); then
            echo "SUSE Prime service not installed. bbswitch can't switch off nvidia card"
            echo "Commands: boot | next-boot | get-boot | service aren't available"
            exit 1;
        else
            echo "SUSE Prime service is DISABLED. bbswitch can't switch off nvidia card"
            echo "Commands: boot | next-boot | get-boot aren't available"
            echo "You can re-enable it using "prime-select service restore""
            exit 1;
        fi
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

function update_kdeglobals {

    # The KDE kscreen5 module ('Display and Monitor' settings) stores the user-defined scaling for all detected monitors
    # in file ~/.config/kdeglobals, in the ScreenScaleFactors line. For example:
    #
    # ScreenScaleFactors=eDP-1-1=2;DP-0=2;DP-1=2;HDMI-0=2;DP-2=2;DP-3=2;DP-4=2;
    #
    # /usr/bin/startkde reads this value and assigns it to environment variable QT_SCREEN_SCALE_FACTORS:
    #
    # QT_SCREEN_SCALE_FACTORS=eDP-1-1=2;DP-0=2;DP-1=2;HDMI-0=2;DP-2=2;DP-3=2;DP-4=2;
    #
    # The value of this variable is crucial to have KDE scale the QT widgets properly 
    #
    # The problem is that the laptop panel output name (eDP-1-1 in that example, always listed first) is not the same depending
    # on whether the intel (modesetting), intel2 (intel) or nvidia driver is used, resulting in that variable
    # not being up-to-date when user switches drivers with this script and scaling not working properly
    #
    # code below is a workaround that edits file ~/.config/kdeglobals with the proper panel name 
    # passed as first parameter of this function

    [ -z "$user" ] && return
    
    panel_name=${1}
    
    kdeglobals="$(sudo -u $user -i eval 'echo -n $HOME')/.config/kdeglobals"
    
    if [ -f $kdeglobals ]; then
	 sudo -u $user sed -i -r "s/(ScreenScaleFactors=)$panel_nvidia|$panel_intel|$panel_intel2/\1$panel_name/" "$kdeglobals"
	 logging "updated $kdeglobals"
    fi    
}

function restore_old_state {
    if [ -f /etc/prime/current_type.old ]; then
        echo "Reconfiguration failed"
        logging "Reconfiguration failed"
        mv -f /etc/prime/current_type.old /etc/prime/current_type
        config=$(cat /etc/prime/current_type)
        echo "Restoring previous configuration: $config"
        logging "Restoring previous configuration: $config"
    else
        echo "Configuration failed"
        logging "Configuration failed"
        rm /etc/prime/current_type
    fi
}

function save_old_state {
    if [ -f /etc/prime/current_type ]; then
        cp -f /etc/prime/current_type /etc/prime/current_type.old
    fi
}

function remove_old_state {
    if [ -f /etc/prime/current_type.old ]; then
        rm /etc/prime/current_type.old
    fi
}

function set_nvidia {

    if (( service_test == 0)); then

    	if [ -f /proc/acpi/bbswitch ]; then        
            tee /proc/acpi/bbswitch > /dev/null <<EOF
ON
EOF
        fi
	
    	logging "trying switch ON nvidia: $(bbcheck)"
        currtime=$(date +"%T");
   	# will also load all necessary dependent modules
    	modprobe nvidia_drm
    	
    	#waits nvidia modules properly loaded
		until [ "$(journalctl --since "$currtime" | grep -E "[nvidia-drm]".*"Loading driver")" > /dev/null ]; do echo; done

    fi    
    
    gpu_info=$(nvidia-xconfig --query-gpu-info)
    # This may easily fail, if no NVIDIA kernel module is available or alike
    if [ $? -ne 0 ]; then
        logging "PCI BusID of NVIDIA card could not be detected!"
        restore_old_state
        exit 1
    fi
    
    # There could be more than on NVIDIA card/GPU; use the first one in that case

    nvidia_busid=$(echo "$gpu_info" | grep -i "PCI BusID" | head -n 1 | sed 's/PCI BusID ://' | sed 's/ //g')

    if [ -f /usr/lib*/xorg/modules/extensions/nvidia/nvidia-libglx.so ]; then
        libglx_nvidia=$(update-alternatives --list libglx.so|grep nvidia-libglx.so)
        update-alternatives --set libglx.so $libglx_nvidia > /dev/null
    fi

    clean_xorg_conf_d 

    cat $xorg_nvidia_conf | sed 's/PCI:X:X:X/'${nvidia_busid}'/' > /etc/X11/xorg.conf.d/90-nvidia.conf

    update_kdeglobals $panel_nvidia
    
    echo "nvidia" > /etc/prime/current_type
    logging "NVIDIA card correctly set"
}

function set_intel {
    # modesetting driver is part of xorg-x11-server and always available
    conf=$xorg_intel_conf_intel
    echo "intel" > /etc/prime/current_type
    #jump to common function intel1/intel2
    common_set_intel
    update_kdeglobals $panel_intel
}

function set_intel2 {
    conf=$xorg_intel_conf_intel2
    echo "intel2" > /etc/prime/current_type
    #jump to common function intel1/intel2
    common_set_intel
    update_kdeglobals $panel_intel2
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
    
    clean_xorg_conf_d
    
    cat $conf | sed -e 's/PCI:X:X:X/'${intel_busid}'/' > /etc/X11/xorg.conf.d/90-intel.conf
    
    if (( service_test == 0)); then
        
        while [ "$(lsmod | grep nvidia)" > /dev/null ]; do
            modprobe -r $nvidia_modules
        done

        if [ -f /proc/acpi/bbswitch ]; then        
            tee /proc/acpi/bbswitch > /dev/null <<EOF 
OFF
EOF
    	logging "NVIDIA card will be switched off, NVIDIA offloading will not be available"
    	fi
	
	logging "trying switch OFF nvidia: $(bbcheck)"
	
    else
        # extra snippet nvidia for NVIDIA's Prime Render Offload mode
        gpu_info=$(nvidia-xconfig --query-gpu-info 2> /dev/null)

    # This may easily fail, if no NVIDIA kernel module is available or alike
        if [ $? -eq 0 -a "$gpu_info" != "" ]; then
            # There could be more than on NVIDIA card/GPU; use the first one in that case
            nvidia_busid=$(echo "$gpu_info" | grep -i "PCI BusID" | head -n 1 | sed 's/PCI BusID ://' | sed 's/ //g')
            logging "Adding support for NVIDIA Prime Render Offload"
            cat $xorg_nvidia_prime_render_offload | sed -e 's/PCI:Y:Y:Y/'${nvidia_busid}'/' >> /etc/X11/xorg.conf.d/90-intel.conf
        else
            logging "PCI BusID of NVIDIA card could not be detected!"
            logging "NVIDIA Prime Render Offload not supported!"
        fi
    fi
    
    libglx_xorg=$(update-alternatives --list libglx.so | grep xorg-libglx.so)

    update-alternatives --set libglx.so $libglx_xorg > /dev/null     
    
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
        elif [ "$current_type" = "nvidia" ] && \
               ! lspci | grep -q "$lspci_nvidia_vga_line" && \
               ! lspci | grep -q "$lspci_nvidia_3d_line"; then
            
            # this can happen if user set nvidia but changed to "Integrated only" in BIOS (possible
            # on some MUXED Optimus laptops) in that case the NVIDIA card is not visible to the
            # system and we must switch to intel
            
            logging "Forcing intel due to NVIDIA card not found"
            current_type="intel"
        fi
        
        
        set_$current_type
    fi
}

function current_check {
    if [ "$(pgrep -f "prime-select user_logout_waiter")" > /dev/null ]; then
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
    logging "HotSwitch: starting Display Manager [ boot_state > N ]"
    systemctl start display-manager &
    systemctl stop prime-select
}

function logout_switch_no_dm {
    apply_current
    echo "N" > /etc/prime/boot_state
    systemctl stop prime-select
}

function set_user {
    [ -n "$1" ] && echo $1 > /etc/prime/user
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
       	    
       	    if ! { [ "$(bbcheck)" = "[bbswitch] NVIDIA card is ON" ] || [ "$(bbcheck)" = "[bbswitch] NVIDIA card is OFF" ]; }; then
    	        bbcheck
            fi
            
            #DM_check
	    
            # use this to determine current target as this is more reliable than legacy runlevel command that can return 'undefined' or 'N'
            # see https://serverfault.com/questions/835515/systemd-how-to-get-the-running-target
            # cannot use 'systemctl get-default' as default target may be different than current target
            target=$(systemctl list-units --type target | egrep "^multi-user|^graphical" | head -1 | cut -f 1 -d ' ')

            # might be empty if script not invoked by sudo, ie directly by root
            user=$SUDO_USER 
	    
            if [ "$target" = "graphical.target" ]; then
            #GDM_mode
            if [ "$(systemctl status display-manager | grep gdm)" > /dev/null ]; then
                $0 user_logout_waiter $type gdm $user &
                logging "user_logout_waiter: started"
		    #SDDM_mode
            elif [ "$(systemctl status display-manager | grep sddm)" > /dev/null ]; then
                $0 user_logout_waiter $type sddm $user &
                logging "user_logout_waiter: started"
		    #lightdm_mode
            elif [ "$(systemctl status display-manager | grep lightdm)" > /dev/null ]; then
                $0 user_logout_waiter $type lightdm $user &
                logging "user_logout_waiter: started"
		    #XDM_mode
            elif [ "$(systemctl status display-manager | grep xdm)" > /dev/null ]; then
                $0 user_logout_waiter $type xdm $user &
                logging "user_logout_waiter: started"
		    #KDM_mode(uses xdm->calls xdm_mode)
            elif [ "$(systemctl status display-manager | grep kdm)" > /dev/null ]; then
                $0 user_logout_waiter $type xdm $user &
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
                        $0 user_logout_waiter $type now $user
                    ;;
                    * ) echo "Aborted. Exit."; exit ;;
                esac
            fi    
            #manually_started_X_case
            elif [ "$target" = "multi-user.target" ] && [ "$(pgrep -x xinit)" > /dev/null ]; then
                $0 user_logout_waiter $type x_only $user &
                logging "user_logout_waiter: started"
            # from console without Xorg running	
            else
                save_old_state
                echo $type > /etc/prime/current_type
                apply_current
                remove_old_state
                exit 
            fi

        else  # no service used

            save_old_state
            echo $type > /etc/prime/current_type
            apply_current
            remove_old_state

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
		set_user $SUDO_USER
 
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
		set_user $SUDO_USER
		
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
	if (( service_test == 0 )); then
		$0 service disable
	fi
	clean_xorg_conf_d
	libglx_xorg=$(update-alternatives --list libglx.so | grep xorg-libglx.so)
	update-alternatives --set libglx.so $libglx_xorg > /dev/null
	rm /etc/prime/current_type &> /dev/null
	rm /etc/prime/boot_state &> /dev/null
	rm /etc/prime/boot &> /dev/null
	rm /etc/prime/forced_boot &> /dev/null
	rm /etc/prime/user &> /dev/null
	rm $prime_logfile &> /dev/null
	;;
    
    service)

	if (( service_test_installed != 0)); then
        echo "SUSE Prime service not installed. bbswitch can't switch off nvidia card"
        echo "Commands: boot | next-boot | get-boot | service aren't available"
        exit 1;
    fi
	
        case $2 in
	    
	    check)
		
                if (( service_test == 0 )); then
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

	echo "S" > /etc/prime/boot_state
	
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
		#systemctl stop display-manager
		
		;;
            
            #manually_started_X_case
            x_only )
		while [ "$(pgrep -x xinit)" > /dev/null ]; do
                    sleep 0.5s
		done
		logging "user_logout_waiter: X stop detected, preparing switch to $2 [ boot_state > S2 ]"

		# S2 = special switch state to indicate that we must not switch to graphical.target (in systemd_call) since we are using xinit/startx
		echo "S2" > /etc/prime/boot_state
		;;

	esac
        
        echo $2 > /etc/prime/current_type
	set_user $4
 
        systemctl stop display-manager
        systemctl start prime-select &
	;;
    
    systemd_call)

	# user is used in update_kdeglobals
	# it is the last user that invoked this script via sudo
	[ -f /etc/prime/user ] && user=$(cat /etc/prime/user) 
	
        #checks if system is booting or switching only
        if [ "$(journalctl -b 0 | grep suse-prime)" > /dev/null ]; then

	    boot_state=$(cat /etc/prime/boot_state)    
	    
	    case $boot_state in

		S)
                    logout_switch
		    ;;
                S2)
		    logout_switch_no_dm
		    ;;
	    esac
	    
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
