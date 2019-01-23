#!/bin/bash

function uninstall
{
    echo -e "\nPreparing to uninstall ..."

    #Service
    echo -e "\nDisabling service ..."
    systemctl disable prime_switch
    echo "Done."
  
    #File install
    echo -e "\nRemoving files ..."
    rm -r                           /etc/prime
    rm                              /etc/systemd/system/prime_switch.service
    rm                              /etc/systemd/system/prime_logout.waiting.service
    rm                              /usr/bin/prime
    rm                              /etc/modprobe.d/optimus-switch.conf
    echo "Done."

    #Modprobe_rules
    echo -e "\nRestoring modprobe rules ..."
    mkinitrd
    echo "Done."
    echo -e "\nScript uninstalled successfully!\n"
}

if [[ $EUID > 0 ]]
    then echo -e "\nPlease run as root\n"
    exit
fi

if [ ! -d /etc/prime/services ] ; then
    echo -e "\nThis script is NOT installed, aborting ...\n"
    exit
fi

echo
read -p "Are you sure that you want to remove SUSEPrime from the system? (y|n): " confirm

case "$confirm" in
    y|Y ) uninstall;;
    n|N ) echo -e "\nAborted\n";;
      * ) echo -e "\nInvalid answer, aborted\n";;
esac
