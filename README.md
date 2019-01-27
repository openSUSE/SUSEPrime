openSUSE nvidia-prime like package
==================================

Assumptions
-----------

* You are running openSUSE Tumbleweed
* You don't have bumblebee installed
* You installed nvidia drivers using http://opensuse-community.org/nvidia.ymp

Installation/usage
------------------

1. Run "prime-select nvidia" log out and login again, hopefully you are
   using nvidia GPU. To switch back to intel GPU run "prime-select intel" (modesetting driver) or 
   "prime-select intel2" (Intel Open Source driver, requires xf86-video-intel package).
   Remember to run as root.
2. To check which GPU you're currently using run "prime-select get-current".
3. In intel configurations, powering off the NVIDIA card with bbswitch to save power and decrease temperature is supported but requires additional manual setup. Refer to instructions below.

Contact
-------

* Bo Simonsen <bo@geekworld.dk>
* Michal Srb <msrb@suse.com>


NVIDIA power off support
-------------------------

Powering off the NVIDIA card when not in use is very efficient for significantly decreasing power consumption (thus increase battery life) and temperature. However, this is complicated by the fact that the card can be powered off
only when the NVIDIA kernel modules are not loaded.

### Install bbswitch

bbswitch is the kernel module that makes it possible to power off the NVIDIA card entirely.
Install it with:

```
zypper in bbswitch
```

### Blacklist the nvidia modules so it can be loaded only when necessary

The NVIDIA openSUSE package adds the NVIDIA driver modules to the kernel initrd image. This will make the system always load them on boot. This is problematic for disabling the NVIDIA card with bbswitch as it can only turn off the card when the modules are not loaded. Instead of unloading the modules before making use of bbswitch, the reverse is way easier: have the NVIDIA modules always unloaded and load them only when needed.
To prevent the modules from being automatically loaded on boot, we need to blacklist them in initrd.
This is easily done with:

```
cp /etc/prime/09-nvidia-blacklist.conf /etc/modprobe.d
dracut -f
```

This will also blacklist the `nouveau` module which can really get in the way with Optimus and causing black screens.

### Install the systemd service for loading NVIDIA module when needed

```
cp /etc/prime/prime-select.service /usr/lib/systemd/system
systemctl enable prime-select
```

This service calls prime-select with whatever driver was previously set by user.
If nvidia is set, it will load the NVIDIA modules before starting the Display Manager (login screen).
Moreover, if an intel config is set but the Intel card was disabled in BIOS (leaving only the dGPU), this service will automatically switch to the nvidia config.


## FAQ

### What are the script parameters to select a driver ?

prime-select `<driver>`

Where `driver` is one of:

- `intel`: uses the modesetting driver
- `intel2`: uses the intel driver (xf86-video-intel). If you use Plasma you might get corrupted flickering display. To fix this make sure to disable vsync in the Plasma compositor settings first. Vsync will be handled by the intel driver
- `nvidia`: use the NVIDIA binary driver


### How do I switch from nvidia to intel with NVIDIA power off support ?


It requires switching runlevels for the script to be able to remove the NVIDIA modules and power off the card:

Exit Xorg, going into runlevel 3 (multi-user):

```
<save all your work in Xorg, close programs as needed>
sudo init 3
<login as root on console>
```

Use the script to change driver:

```
prime-select intel
```

Restart in run level 5 (graphical mode) with the new driver:

```
init 5
```

### How to I check that the NVIDIA card is powered off ?

```
cat /proc/acpi/bbswitch 
0000:01:00.0 OFF
```


