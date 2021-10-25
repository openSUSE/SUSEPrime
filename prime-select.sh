#!/bin/bash

# Script for selecting either nvidia og intel card for NVIDIA optimus laptops
# Please follow instructions given in README

# Public domain by Bo Simonsen <bo@geekworld.dk>
# Adapted for OpenSUSE Tumbleweed by Michal Srb <msrb@suse.com>
# Extended for TUXEDO Computers by Vinzenz Vietzke <vv@tuxedocomputers.com>
# Augmented by bubbleguuum <bubbleguuum@free.fr>
# Improved by simopil <pilia.simone96@gmail.com>

type=$1
xorg_nvidia_conf="/usr/share/prime/xorg-nvidia.conf"
xorg_intel_conf_intel="/usr/share/prime/xorg-intel.conf"
xorg_intel_conf_intel2="/usr/share/prime/xorg-intel-intel.conf"
xorg_amd_conf="/usr/share/prime/xorg-amd.conf"
xorg_nvidia_prime_render_offload="/usr/share/prime/xorg-nvidia-prime-render-offload.conf"
prime_logfile="/var/log/prime-select.log"
nvidia_modules="nvidia_drm nvidia_modeset nvidia_uvm nvidia"
driver_choices="nvidia|intel|intel2|amd|offload"
lspci_intel_line="VGA compatible controller: Intel"
lspci_amd_line="VGA compatible controller: Advanced Micro Devices"
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
    panel_amd=eDP-1
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

# Make sure /etc/prime exists, so /etc/prime/current_type can be written
test -d /etc/prime || mkdir -p /etc/prime

# Make sure tools like modinfo are found also by non-root users (issue#72)
if (( $EUID != 0 )); then
    export PATH=/sbin:/usr/sbin:$PATH
fi

function usage {
    echo
    echo "NVIDIA/Intel video card selection for NVIDIA Optimus laptops."
    echo

    if (( service_test == 0 )); then
        echo "usage: $(basename $0)           $driver_choices|unset|get-current|get-boot|offload-set|log-view|log-clean"
        echo "usage: $(basename $0) boot      $driver_choices|last"
        echo "usage: $(basename $0) next-boot $driver_choices|abort"
        echo "usage: $(basename $0) service   check|disable|restore"
    else
        echo "usage: $(basename $0) $driver_choices|unset|get-current|offload-set|log-view|log-clean"
    fi

    echo
    echo "nvidia:      use the NVIDIA proprietary driver"
    echo "intel:       use the Intel card with the \"modesetting\" driver"
    echo "intel2:      use the Intel card with the \"intel\" Open Source driver (xf86-video-intel)"
    echo "amd:         use the Amd card with the \"amd\" Open Source driver (xf86-video-amdgpu)"
    echo "offload      PRIME Render Offload possible with >= 435.xx NVIDIA driver"
    echo "offload-set  choose which intel driver use in PRIME Render Offload"
    echo "unset:       disable effects of this script and let Xorg decide what driver to use"
    echo "get-current: display driver currently configured"
    echo "log-view:    view logfile"
    echo "log-clean:   clean logfile"

    if (( service_test_installed == 0 )); then
        echo "boot:        select default card at boot or set last used"
        echo "             supports kernel parameter nvidia.prime=intel|intel2|nvidia|amd|offload"
        echo "next-boot:   select card ONLY for next boot, it not touches your boot preference. abort: restores next boot to default"
        echo "get-boot:    display default card at boot"
        echo "service:     disable, check or restore prime-select service."
    fi
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
            #echo "SUSE Prime service not installed. bbswitch can't switch off nvidia card"
            echo "Commands: boot | next-boot | get-boot | service aren't available"
            exit 1;
        else
            #echo "SUSE Prime service is DISABLED. bbswitch can't switch off nvidia card"
            echo "Commands: boot | next-boot | get-boot aren't available"
            echo "You can re-enable it using "prime-select service restore""
            exit 1;
        fi
    fi
}

function nv_offload_capable {
    #checks if nvidia driver version is offload capable (>=435.00)
    (( $(modinfo nvidia | grep ^version: | awk '{print $2}' | tr -d .) >= 43500 ))
}

function offload_pref_check {
    #checks if there's a preference for nvidia-offloading
    if ! [ -f /etc/prime/offload_type ]; then
        echo "intel" > /etc/prime/offload_type
        logging "Using default intel modesetting driver for offloading."
    fi
}

function bbcheck {
    #searching module is better than rpm package because there are other bbswitch providers like dkms-bbswitch
    if ! [ $(modinfo bbswitch 2> /dev/null | wc -c) = 0 ]; then
        if ! [ "$(lsmod | grep bbswitch)" > /dev/null ]; then
            if [ "$(lsmod | grep nvidia_drm)" > /dev/null ]; then
                echo "bbswitch not loaded. NVIDIA modules are loaded"
            else
                echo "bbswitch not loaded. NVIDIA modules are NOT loaded"
                echo "if you want energy saving bbswitch should be loaded in intel mode"
            fi
        else
            if grep OFF /proc/acpi/bbswitch > /dev/null; then
                echo "[bbswitch] NVIDIA card is OFF"
            elif grep ON /proc/acpi/bbswitch > /dev/null; then
                #never happens 'cause bbswitch should not be loaded in nvidia/offload mode
                echo "[bbswitch] NVIDIA card is ON"
            else
                #never happens?
                echo "bbswitch is running but seems broken. Cannot get NVIDIA power status"
            fi
        fi
    else
        #should never happen with suse-prime-bbswitch package as bbswitch is a dependency
        echo "bbswitch module not found. NVIDIA card will not be powered off"
    fi
}

function nvpwr {
    #parameter set to 1 (unload bbswitch and keep nvidia ON)
    #parameter set to 0 (load bbswitch with load_state=0 and unload_state=1)
    if [ "${1}" = "1" ]; then
        if lsmod | grep bbswitch > /dev/null; then
            if [ $(cat /sys/module/bbswitch/parameters/unload_state) == 1 ]; then
                logging "Unloading bbswitch and switching nvidia ON..."
                modprobe -r bbswitch
            else
                #should never happens
                tee /proc/acpi/bbswitch <<<ON
                logging "trying switch ON nvidia: $(bbcheck)"
            fi
        fi
    else
        if ! lsmod | grep bbswitch > /dev/null; then
            modprobe bbswitch load_state=0 unload_state=1
        else
            #should never happens
            tee /proc/acpi/bbswitch <<<OFF
        fi
        logging "NVIDIA card will be switched off, NVIDIA offloading will not be available"
        logging "trying switch OFF nvidia: $(bbcheck)"
    fi
}

function clean_xorg_conf_d {
    rm -f /etc/X11/xorg.conf.d/90-nvidia.conf
    rm -f /etc/X11/xorg.conf.d/90-intel.conf
    rm -f /etc/X11/xorg.conf.d/90-amd.conf
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

    nvpwr 1
    if ! lsmod | grep nvidia > /dev/null; then
        # will also load all necessary dependent modules
        #waits nvidia modules properly loaded
        #protect until cycle from infinite loop
        currtime=$(date +"%T");
        modprobe nvidia_drm
        SECONDS=0
        until [ "$(journalctl --since "$currtime" | grep -E "[nvidia-drm]".*"Loading driver")" > /dev/null ]; do
            if (($SECONDS > 7)); then
                logging "ERROR: cannot load nvidia modules [timed out]"
                break
            fi
        done
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
    if ! [ "$(cat /etc/prime/current_type)" = "offload" ]; then
        echo "intel" > /etc/prime/current_type
    fi
    #jump to common function intel1/intel2
    common_set "${lspci_intel_line}" 'Intel'
    update_kdeglobals $panel_intel
}

function set_intel2 {
    conf=$xorg_intel_conf_intel2
    if ! [ "$(cat /etc/prime/current_type)" = "offload" ]; then
        echo "intel2" > /etc/prime/current_type
    fi
    #jump to common function intel1/intel2
    common_set "${lspci_intel_line}" 'Intel'
    update_kdeglobals $panel_intel2
}

function set_amd {
    conf=$xorg_amd_conf
    if ! [ "$(cat /etc/prime/current_type)" = "offload" ]; then
        echo "amd" > /etc/prime/current_type
    fi
    common_set "${lspci_amd_line}" 'Amd'
    update_kdeglobals $panel_amd

}


function common_set {
    # find Intel card bus id. Without this Xorg may fail to start
    lspci_line=$1
    constructor=$2
    lowercase_constructor=$(echo $constructor | tr '[A-Z]' '[a-z]')
    line=$(lspci | grep "$lspci_line" | head -1)
    if [ $? -ne 0 ]; then
        logging "Failed to find $constructor card with lspci"
        exit 1
    fi

    card_busid=$(echo $line | cut -f 1 -d ' ' | sed -e 's/\./:/g;s/:/ /g' | awk -Wposix '{printf("PCI:%d:%d:%d\n","0x" $1, "0x" $2, "0x" $3 )}')
    if [ $? -ne 0 ]; then
        logging "Failed to build $constructor card bus id"
        exit 1
    fi

    clean_xorg_conf_d

    cat $conf | sed -e 's/PCI:X:X:X/'${card_busid}'/' > /etc/X11/xorg.conf.d/90-${lowercase_constructor}.conf

    if [ "$(cat /etc/prime/current_type)" = "offload" ]; then
        nvpwr 1
        if ! lsmod | grep nvidia > /dev/null; then
            logging "Loading nvidia_modules"
            modprobe nvidia_modeset
        fi
        # extra snippet nvidia for NVIDIA's Prime Render Offload mode
        gpu_info=$(nvidia-xconfig --query-gpu-info 2> /dev/null)

        # This may easily fail, if no NVIDIA kernel module is available or alike
        if [ $? -eq 0 -a "$gpu_info" != "" ]; then
            # There could be more than on NVIDIA card/GPU; use the first one in that case
            nvidia_busid=$(echo "$gpu_info" | grep -i "PCI BusID" | head -n 1 | sed 's/PCI BusID ://' | sed 's/ //g')
            logging "Adding support for NVIDIA Prime Render Offload"
            cat $xorg_nvidia_prime_render_offload | sed -e 's/PCI:Y:Y:Y/'${nvidia_busid}'/' >> /etc/X11/xorg.conf.d/90-${lowercase_constructor}.conf
        else
            logging "PCI BusID of NVIDIA card could not be detected!"
            logging "NVIDIA Prime Render Offload not supported!"
        fi
    else
        # https://github.com/Bumblebee-Project/bbswitch/issues/173#issuecomment-703162468
        # ensure nvidia-persistenced service is not running
        if systemctl is-active --quiet nvidia-persistenced.service; then
            systemctl stop nvidia-persistenced.service
            systemctl disable nvidia-persistenced.service
        fi
        # kill all nvidia related process to fix failure to unload nvidia modules (issue#50)
        nvidia_process=$(lsof -t /dev/nvidia* 2> /dev/null)
        if [ -n "$nvidia_process" ]; then
            kill -9 $nvidia_process
        fi
        # try only n times; avoid endless loop which may block system updates forever (boo#1173632)
        last=3
        for try in $(seq 1 $last); do
            modprobe -r $nvidia_modules && break
            if [ $try -eq $last ]; then
                echo "NVIDIA kernel modules cannot be unloaded (tried $last times). Your machine may need a reboot."
            fi
        done
        nvpwr 0
    fi

    libglx_xorg=$(update-alternatives --list libglx.so | grep xorg-libglx.so)

    update-alternatives --set libglx.so $libglx_xorg > /dev/null

    logging "$constructor card correctly set"
}


function apply_current {
    if [ -f /etc/prime/current_type ]; then

        current_type=$(cat /etc/prime/current_type)

        if [ "$current_type" == "intel"  ] || [ "$current_type" == "intel2"  ]
        then

        if  ! lspci | grep "$lspci_intel_line" > /dev/null; then

            # this can happen if user set intel but changed to "Discrete only" in BIOS
            # in that case the Intel card is not visible to the system and we must switch to nvidia

            logging "Forcing nvidia due to Intel card not found"
            current_type="nvidia"
        fi

        elif [ "$current_type" == "amd"  ] && ! lspci | grep "$lspci_amd_line" > /dev/null; then

            # this can happen if user set intel but changed to "Discrete only" in BIOS
            # in that case the Intel card is not visible to the system and we must switch to nvidia

            logging "Forcing nvidia due to Amd card not found"
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



        if [ "$current_type" = "offload" ]; then
            offload_pref_check
            set_$(cat /etc/prime/offload_type)
        else
            set_$current_type
        fi
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
        if [ "$type" = "offload" ]; then
            if [[ "$(cat /etc/prime/offload_type)" = "intel" && "$(cat /etc/X11/xorg.conf.d/90-intel.conf | grep "Driver \"modesetting\"")" > /dev/null ]] ||
               [[ "$(cat /etc/prime/offload_type)" = "intel2" && "$(cat /etc/X11/xorg.conf.d/90-intel.conf | grep "Driver \"intel\"")" > /dev/null ]]; then
                echo "NVIDIA offloading with $(cat /etc/prime/offload_type) already in use!"
                exit 1
            fi
        else
            echo "$type driver already in use!"
            exit 1
        fi
    fi
}

function logout_switch {
    apply_current
    logging "HotSwitch: starting Display Manager"
    systemctl start display-manager
    logging "HotSwitch: completed!"
}

function logout_switch_no_dm {
    apply_current
    logging "HotSwitch: completed!"
}

function set_user {
    [ -n "$1" ] && echo $1 > /etc/prime/user
}

case $type in

    nvidia|intel|intel2|offload|amd)
        echo $type catched
        current_check
        check_root

        if [ $type = "offload" ]; then
            if ! nv_offload_capable; then
                echo "ERROR: offloading needs nvidia drivers >= 435.xx"
                exit 1
            fi
        fi

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

        if [ "$type" = "amd" ];then
            if ! rpm -q xf86-video-amdgpu > /dev/null; then
                echo "package xf86-video-amdgpu is not installed";
                exit 1
            fi
        fi

        if ! { [ "$(bbcheck)" = "[bbswitch] NVIDIA card is ON" ] || [ "$(bbcheck)" = "[bbswitch] NVIDIA card is OFF" ]; }; then
            bbcheck
        fi

        # might be empty if script not invoked by sudo, ie directly by root
        user=$SUDO_USER
        #DM_check
        if systemctl is-active graphical.target > /dev/null; then
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
            elif [ "$(systemctl is-active multi-user.target)" > /dev/null ] && [ "$(pgrep -x xinit)" > /dev/null ]; then
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
        echo -e "Logout to switch graphics"
    ;;

    offload-set)

        if [ "$2" = "intel2" ]; then
            if ! rpm -q xf86-video-intel > /dev/null; then
                echo "package xf86-video-intel is not installed";
                exit 1
            fi
        fi

        if [ "$2" = "amd" ];then
            if ! rpm -q xf86-video-amdgpu > /dev/null; then
                echo "package xf86-video-amdgpu is not installed";
                exit 1
            fi
        fi

        if ! nv_offload_capable; then
            echo "ERROR: offloading needs nvidia drivers >= 435.xx"
            exit 1
        fi
        case $2 in
            intel|intel2)
                echo $2 > /etc/prime/offload_type
                echo "nvidia-offload is now available with $2 driver"
                echo "use it with \"prime-select offload\""
            ;;
            *)
                echo "Only intel|intel2 driver is available in nvidia-offload!"
            ;;
        esac
    ;;

    boot)

        check_service
        check_root

        case $2 in

            nvidia|intel|intel2|amd|last|offload)

                if [ "$2" = "intel2" ]; then
                    if ! rpm -q xf86-video-intel > /dev/null; then
                        echo "package xf86-video-intel is not installed";
                        exit 1
                    fi
                fi

                if [ "$2" = "amd" ];then
                    if ! rpm -q xf86-video-amdgpu > /dev/null; then
                        echo "package xf86-video-amdgpu is not installed";
                        exit 1
                    fi
                fi

                if [ $2 = "offload" ]; then
                    if ! nv_offload_capable; then
                        echo "ERROR: offloading needs nvidia drivers >= 435.xx"
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

            nvidia|intel|intel2|amd|offload)

                if [ "$2" = "intel2" ]; then
                    if ! rpm -q xf86-video-intel > /dev/null; then
                        echo "package xf86-video-intel is not installed";
                        exit 1
                    fi
                fi

                if [ "$2" = "amd" ];then
                    if ! rpm -q xf86-video-amdgpu > /dev/null; then
                        echo "package xf86-video-amdgpu is not installed";
                        exit 1
                    fi
                fi
                if [ $2 = "offload" ]; then
                    if ! nv_offload_capable; then
                        echo "ERROR: offloading needs nvidia drivers >= 435.xx"
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
        rm /etc/prime/offload_type &> /dev/null
        rm /etc/prime/boot &> /dev/null
        rm /etc/prime/forced_boot &> /dev/null
        rm /etc/prime/user &> /dev/null
        rm $prime_logfile &> /dev/null
    ;;

    service)

        if (( service_test_installed != 0)); then
            #echo "SUSE Prime service not installed. bbswitch can't switch off nvidia card"
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

        currtime=$(date +"%T");
        dm_func=logout_switch
        #manage journalctl to check when X restarted, then jump init 3
        case "$3" in

            gdm )
                #GDM_mode
                until [ "$(journalctl --since "$currtime" | grep -e "pam_unix(gdm-password:session): session closed" \
                                                                 -e "pam_unix(gdm-autologin:session): session closed")" > /dev/null ]; do
                    sleep 0.5s
                done
                logging "user_logout_waiter: X restart detected, preparing switch to $2"
            ;;

            sddm )
                #SDDM_mode
                until [ "$(journalctl --since "$currtime" -e _COMM=sddm | grep "Removing display")" > /dev/null ]; do
                    sleep 0.5s
                done
                logging "user_logout_waiter: X restart detected, preparing switch to $2"
            ;;

            lightdm  )
                #lightdm_mode
                until [ "$(journalctl --since "$currtime" -e | grep "pam_unix(lightdm:session): session closed")" > /dev/null ]; do
                    sleep 0.5s
                done
                logging "user_logout_waiter: X restart detected, preparing switch to $2"
            ;;

            xdm )
                #xdm/kdm_mode
                until [ "$(journalctl --since "$currtime" -e | grep "pam_unix(xdm:session): session closed for user")" > /dev/null ]; do
                    sleep 0.5s
                done
                logging "user_logout_waiter: X restart detected, preparing switch to $2"
            ;;

            x_only )
                #manually_started_X_case
                while [ "$(pgrep -x xinit)" > /dev/null ]; do
                    sleep 0.5s
                done
                logging "user_logout_waiter: X stop detected, preparing switch to $2"
                dm_func=logout_switch_no_dm
            ;;
        esac

        echo $2 > /etc/prime/current_type
        set_user $4
        systemctl stop display-manager
        #calling logout_switch or logout_switch_no_dm based on dm_func variable
        $dm_func
    ;;

    systemd_call)

        # user is used in update_kdeglobals
        # it is the last user that invoked this script via sudo
        [ -f /etc/prime/user ] && user=$(cat /etc/prime/user)

        #checks if system is booting or switching only
        #boot priority is forced boot > kernel parameter > boot preference
        if ! journalctl -b 0 | grep suse-prime > /dev/null; then
            if [ -f /etc/prime/forced_boot ]; then
                echo "$(cat /etc/prime/forced_boot)" > /etc/prime/current_type
                rm /etc/prime/forced_boot
                logging "Boot: forcing booting with $(cat /etc/prime/current_type), boot preference ignored"
            else
                #search kernel "nvidia.prime=intel|intel2|nvidia|amd|offload" parameter
                kparam=$(grep -oP 'nvidia.prime=\K\S+' /proc/cmdline)
                if [ "$kparam" > /dev/null ]; then
                    case "$kparam" in
                        intel|nvidia)
                            logging "Boot: nvidia.prime="$kparam" kernel parameter detected!"
                            echo "$kparam" > /etc/prime/current_type
                        ;;
                        intel2)
                            if ! rpm -q xf86-video-intel > /dev/null; then
                                logging "Boot: package xf86-video-intel is not installed, ignoring";
                            else
                                logging "Boot: nvidia.prime="$kparam" kernel parameter detected!"
                                echo "$kparam" > /etc/prime/current_type
                            fi
                        ;;
                        offload)
                            if ! nv_offload_capable; then
                                logging "Boot: offloading needs nvidia drivers >= 435.xx, ignoring kernel parameter"
                            else
                                echo "$kparam" > /etc/prime/current_type
                                logging "Boot: nvidia.prime="$kparam" kernel parameter detected!"
                            fi
                        ;;
                    esac
                else
                    if ! [ -f /etc/prime/boot ]; then
                        echo "last" > /etc/prime/boot
                    fi
                    boot_type=$(cat /etc/prime/boot)
                    if [ "$boot_type" != "last" ]; then
                        echo "$boot_type" > /etc/prime/current_type
                    fi
                fi
                logging "Boot: setting-up $(cat /etc/prime/current_type) card"
            fi
            logout_switch_no_dm
        fi
    ;;

    get-boot)

        check_service
        if [ -f /etc/prime/boot ]; then
            echo "Default at system boot: $(cat /etc/prime/boot)"
        else
            echo "Default at system boot: auto (last)"
            echo "You can configure it with prime-select boot intel|intel2|nvidia|amd|last"
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
