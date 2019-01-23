OpenSUSE nvidia-prime like package
==================================

Assumptions
-----------

* You are running OpenSUSE Tumbleweed
* You don't have bumblebee installed
* You installed nvidia drivers using http://opensuse-community.org/nvidia.ymp

DESCRIPTION:

What's suse-prime?
SUSE-PRIME: a tool that lets you choose intel or nvidia card for X session in a Optimus technology laptop, performances are better than bumblebee. (https://github.com/openSUSE/SUSEPrime/)  (OLD https://github.com/michalsrb/SUSEPrime)

My script provides: 

>> Extended battery life and cooler temperatures, because suse-prime DO NOT put nvidia card in sleep mode when intel one is active. This feature is provided by Nouveau driver, without bumblebee or any ACPI Switch

>> A choice to change default vga on boot, or remember the latest session

REQUIREMENTS:

Nvidia proprietary drivers: https://en.opensuse.org/SDB:NVIDIA_drivers

USAGE:

prime switch [intel | nvidia ]           >> [ROOT] system waits for logout to switch video card

prime default [intel | nvidia | keep]    >> [ROOT] set default vga on boot (keep > remember latest session)

prime query                              >> show current gpu and boot settings

Tested on Optimus laptop with opensuse Tumbleweed and latest kernel (4.12 also works)
suse-prime package not required, already included.

Contact
-------

* Bo Simonsen <bo@geekworld.dk>
* Michal Srb <msrb@suse.com>
* simopil <pilia.simone96@gmail.com>

File Paths

RULES
>> "optimus-switch.conf"      /etc/modprobe.d/    ||  modprobe rules for boot and modesetting
        
EXECUTABLES
>> "prime"                 /usr/bin/           ||   executable tool, provides you all options
 
CONFIG_FILES
>> "config"              /etc/prime/         ||   main configuration file with all settings, DO NOT EDIT

>> "xorg-intel.conf"     /etc/prime/         ||   suse-prime xorg config file of SUSEPrime project (michalsrb)

>> "xorg-nvidia.conf"    /etc/prime/         ||   suse-prime xorg config file of SUSEPrime project (michalsrb)
 
 
 
SERVICES
 
>> "prime_logout.waiting"   /etc/prime/services/    ||   service that waits you logout to switch graphics

>> "prime_switch"           /etc/prime/services/    ||   core of entire script
 
>> "prime-select.sh"        /etc/prime/services/    ||   prime-select executable of SUSEPrime project (michalsrb)
  


SERVICES_CONFIG 

>> "prime_logout.waiting.service"    /etc/systemd/system/     ||   service that waits you logout to switch graphics [CONFIG]

>> "prime_switch.service"            /etc/systemd/system/     ||   core of entire script [CONFIG]
