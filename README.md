openSUSE nvidia-prime like package
==================================

Assumptions
-----------

* You are running openSUSE Tumbleweed
* You don't have bumblebee installed
* You installed NVIDIA drivers using http://opensuse-community.org/nvidia.ymp

Installation/usage
------------------

1. Run `sudo prime-select nvidia` log out and login again, hopefully you are
   using the NVIDIA card. To switch back to te Intel card run `sudo prime-select intel` (modesetting driver) or 
   `sudo prime-select intel2` (Intel Open Source driver, requires xf86-video-intel package).
2. To check which video card you're currently using run `/usr/sbin/prime-select get-current`.
3. On intel configurations, powering off the NVIDIA card with bbswitch (legacy 390.xxx driver) or DynamicPowerManagement option (435.xx driver and later) to save power and decrease temperature is supported but requires additional manual setup. Refer to instructions below.
4. With current 435.xx driver and later you can make use of NVIDIA's PRIME Render Offload feature in intel configurations. `Option "AllowNVIDIAGPUScreens"` is already taken care of by intel X configs. You only need to set the __NV* environment variables. Check <https://download.nvidia.com/XFree86/Linux-x86_64/435.21/README/primerenderoffload.html> for more details.

Contact
-------

* Bo Simonsen <bo@geekworld.dk>
* Michal Srb <msrb@suse.com>

Related projects
----------------

* SUSEPrimeQT <https://github.com/simopil/SUSEPrimeQt/> Provides a simple GUI for SUSEPrime

NVIDIA power off support with 435.xxx driver and later (=G05 driver packages)
-----------------------------------------------------------------------------

Recreate your initrd with some special settings, which are needed to enable DynamicPowerManagement and remove NVIDIA kernel modules from initrd, so some special udev rules can be applied to disable NVIDIA Audio and NVIDIA USB and make runtime PM for NVIDIA GPU active. This is needed as workaround, since NVIDIA Audio/USB currently cannot be enabled at the same time as NVIDIA GPU DynamicPowerManagement. This is easily done with:

```
test -s /etc/modprobe.d/09-nvidia-modprobe-pm-G05.conf  || \
  cp 09-nvidia-modprobe-pm-G05.conf /etc/modprobe.d
if [ ! -s /etc/dracut.conf.d/90-nvidia-dracut-G05.conf ]; then
  cp 90-nvidia-dracut-G05.conf /etc/dracut.conf.d/ && dracut -f
fi
test -s /etc/udev/rules.d/90-nvidia-udev-pm-G05.rules || \
  cp 90-nvidia-udev-pm-G05.rules /etc/udev/rules.d/
```

NVIDIA power off support with 390.xxx driver (=G04 legacy driver packages)
--------------------------------------------------------------------------

Powering off the NVIDIA card when not in use is very efficient for significantly decreasing power consumption (thus increase battery life) and temperature. However, this is complicated by the fact that the card can be powered off
only when the NVIDIA kernel modules are not loaded.

### Install bbswitch

bbswitch is the kernel module that makes it possible to power off the NVIDIA card entirely.
Install it with:

```
zypper in bbswitch
```

### Blacklist the NVIDIA modules so it can be loaded only when necessary

The NVIDIA openSUSE package adds the NVIDIA driver modules to the kernel initrd image. This will make the system always load them on boot. This is problematic for disabling the NVIDIA card with bbswitch as it can only turn off the card when the modules are not loaded. Instead of unloading the modules before making use of bbswitch, the reverse is way easier: have the NVIDIA modules always unloaded and load them only when needed.
To prevent the modules from being automatically loaded on boot, we need to blacklist them in initrd.
This is easily done with:

```
if [ ! test -s /etc/modprobe.d/09-nvidia-modprobe-bbswitch-G04.conf ]; then
  cp 09-nvidia-modprobe-bbswitch-G04.conf /etc/modprobe.d && dracut -f
fi
```

This will also blacklist the `nouveau` module which can really get in the way with Optimus and causing black screens.

### Install the systemd services for doing switch and set correct card during boot

```
if [ ! -s /usr/lib/systemd/system/prime-select.service ]; then
  cp prime-select.service /usr/lib/systemd/system && \
  systemctl enable prime-select
fi
```

If nvidia is set, it will load the NVIDIA modules before starting the Graphical Target.
Moreover, if an intel config is set but the Intel card was disabled in BIOS (leaving only the dGPU), this service will automatically switch to the nvidia config.
The reverse is also true (nvidia config set but BIOS configured to use iGPU only).


## FAQ

### How do I select a driver ?

sudo prime-select `<driver>`

Where `<driver>` is one of:

- `intel`: use the `modesetting` driver (PRIME Render Offload possible with >= 435.xx driver)
- `intel2`: use the `intel` driver (xf86-video-intel) (PRIME Render Offload possible with >= 435.xx driver)
- `nvidia`: use the NVIDIA proprietary driver


### How do I check the current driver configured and the power state of the NVIDIA card (390.xxx legacy driver)?

```
/usr/sbin/prime-select get-current
Driver configured: intel
[bbswitch] NVIDIA card is OFF
```

To get more details on the Xorg driver, install package `inxi` if necessary and use `inxi -G`:

```
inxi -G
Graphics:  Device-1: Intel UHD Graphics 630 driver: i915 v: kernel 
           Device-2: NVIDIA GP107GLM [Quadro P600 Mobile] driver: N/A 
           Display: x11 server: X.Org 1.20.4 driver: intel resolution: 3840x2160~60Hz 
           OpenGL: renderer: Mesa DRI Intel UHD Graphics 630 (Coffeelake 3x8 GT2) v: 4.5 Mesa 18.3.4
```
