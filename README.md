OpenSUSE nvidia-prime like package
==================================

Assumptions
-----------

* You are running OpenSUSE LEAP 42.1
* You don't have bumblebee installed
* You installed nvidia drivers using http://opensuse-community.org/nvidia.ymp

Installation/usage
------------------

1. Put the content of this package somewhere (I used /root/opensuse-nvidia-prime)
2. Added the following lines 

    if [ -f /etc/X11/xinit/xinitrc.d/prime-offload.sh ];
    then
        . /etc/X11/xinit/xinitrc.d/prime-offload.sh
    fi

    To /etc/X11/xdm/Xsetup after the line ". /etc/sysconfig/displaymanager"

3. Run "bash prime-select.sh nvidia" log out and login again, hopefully you are
   using nvidia GPU. To switch back to intel GPU run "bash prime-select.sh intel"
   Remember to run as root.

Contact
-------

* Bo Simonsen <bo@geekworld.dk>


