#!/bin/bash

function setup
{
    echo -e "\nPreparing to install ..."
  
    #File install
    echo -e "\nCopying files ..."
    mkdir                                         /etc/prime
    mkdir                                         /etc/prime/services
    cp config                                     /etc/prime/config
    cp prime_switch                               /etc/prime/services/prime_switch
    cp prime_logout.waiting                       /etc/prime/services/prime_logout.waiting
    cp prime_switch.service                       /etc/systemd/system/prime_switch.service
    cp prime_logout.waiting.service               /etc/systemd/system/prime_logout.waiting.service
    cp prime                                      /usr/bin/prime
    cp optimus-switch.conf                        /etc/modprobe.d/optimus-switch.conf
    cp prime-select.sh                            /etc/prime/services/prime-select.sh
    cp xorg-intel.conf                            /etc/prime/xorg-intel.conf
    cp xorg-nvidia.conf                           /etc/prime/xorg-nvidia.conf
    echo "Done."
  
    #Permissions
    echo -e "\nSetting permissions ..."
    chmod +x /etc/prime/services/prime_switch
    chmod +x /etc/prime/services/prime_logout.waiting
    chmod +x /etc/prime/services/prime-select.sh
    chmod +x /usr/bin/prime
    echo "Done."
  
    #Service
    echo -e "\nSetting service ..."
    systemctl enable prime_switch
    bash /etc/prime/services/prime-select.sh intel
    echo "Done."
  
    #Modprobe_rules
    echo -e "\nSetting modprobe rules ..."
    mkinitrd
    echo "Done."
    
    echo -e "\nInstallation completed successfully! Please REBOOT and use [ prime ] command to know how to use\n"
}

echo
if [[ $EUID > 0 ]]
    then echo -e "Please run as root\n"
    exit
fi

echo -e "Welcome to SUSEPrime installation! Based to original SUSEPrime and nvidia-optimus-switch project."
echo -e "Please visit https://github.com/openSUSE/SUSEPrime"
echo -e "\nPreliminary verification ..."

if [ -x "$(command -v prime-select)" ]; then
    echo -e "\nsuse-prime package not required, already included in this project! Uninstall it first" >&2
    exit 1
fi

if [ -x "$(command -v optirun)" ]; then
    echo -e "\nSeems you have bumblebee or similar installed, please remove it first!" >&2
    exit 1
fi

echo
read -p "SUSEPrime will be installed on your system, continue? (y|n): " confirm

case "$confirm" in
    y|Y ) setup;;
    n|N ) echo -e "\nInstallation aborted\n";;
      * ) echo -e "\nInvalid answer, installation aborted\n";;
esac
