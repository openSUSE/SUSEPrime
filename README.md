openSUSE nvidia-prime like package
==================================

Assumptions
-----------

* You are running openSUSE Leap 15.1 or later (Xserver of Leap 15.2 or later for NVIDIA's PRIME render offload support)
* You don't have bumblebee installed
* You installed NVIDIA drivers using http://opensuse-community.org/nvidia.ymp

Installation/usage
------------------

1. Run `sudo prime-select nvidia` log out and login again, hopefully you are
   using the NVIDIA card. To switch back to te Intel card run `sudo prime-select intel` (modesetting driver) or 
   `sudo prime-select intel2` (Intel Open Source driver, requires xf86-video-intel package).
2. To check which video card you're currently using run `/usr/sbin/prime-select get-current`.
3. In intel-only mode, powering off the NVIDIA card with bbswitch (since 390.xxx driver) is supported. Using DynamicPowerManagement option in nvidia/intel mode  (since 435.xx driver and Turing GPU or later) to save power and decrease temperature is supported but requires additional manual setup. Refer to instructions below.
4. Since 435.xx driver you can make use of NVIDIA's PRIME Render Offload feature in intel configurations (Xserver of Leap 15.2 or later needed!). `Option "AllowNVIDIAGPUScreens"` is already taken care of by intel X configs. You only need to set the __NV* environment variables. Check <https://download.nvidia.com/XFree86/Linux-x86_64/435.21/README/primerenderoffload.html> for more details.

Contact
-------

* Bo Simonsen <bo@geekworld.dk>
* Michal Srb <msrb@suse.com>
* Simone Pilia <pilia.simone96@gmail.com>

Related projects
----------------

* SUSEPrimeQT <https://github.com/simopil/SUSEPrimeQt/> Provides a simple GUI for SUSEPrime

NVIDIA power off support since 435.xxx driver with Turing GPU and later (G05 driver packages)
----------------------------------------------------------------------------------------------

For detailed requirements of this feature see chapter "PCI-Express Runtime D3 (RTD3) Power Management", section "SUPPORTED CONFIGURATIONS" of NVIDIA driver's README.txt.

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

NVIDIA power off support since 390.xxx driver (G04/G05 driver packages)
-----------------------------------------------------------------------

Powering off the NVIDIA card when not in use is very efficient for significantly decreasing power consumption (thus increase battery life) and temperature. However, this is complicated by the fact that the card can be powered off
only when the NVIDIA kernel modules are not loaded.

### Install bbswitch

bbswitch is the kernel module that makes it possible to power off the NVIDIA card entirely.
Install it with:

```
zypper in bbswitch
```
* bbswitch module must be blacklisted, even in initrd, prime-select will load it only when needed

### Blacklist the NVIDIA modules so it can be loaded only when necessary

The NVIDIA openSUSE package adds the NVIDIA driver modules to the kernel initrd image. This will make the system always load them on boot. This is problematic for disabling the NVIDIA card with bbswitch as it can only turn off the card when the modules are not loaded. Instead of unloading the modules before making use of bbswitch, the reverse is way easier: have the NVIDIA modules always unloaded and load them only when needed.
To prevent the modules from being automatically loaded on boot, we need to blacklist them in initrd.
This is easily done with:

```
if [ ! -s /etc/modprobe.d/09-nvidia-modprobe-bbswitch-G04.conf ]; then
  cp 09-nvidia-modprobe-bbswitch-G04.conf /etc/modprobe.d && dracut -f
fi
```

This will also blacklist the `nouveau` module which can really get in the way with Optimus and causing black screens.

### Install the systemd services to set correct card during boot

```
if [ ! -s /usr/lib/systemd/system/prime-select.service ]; then
  cp prime-select.service /usr/lib/systemd/system && \
  systemctl enable prime-select
fi
```

- If nvidia is set, it will load the NVIDIA modules before starting the Graphical Target.
Moreover, if an intel config is set but the Intel card was disabled in BIOS (leaving only the dGPU), this service will automatically switch to the nvidia config.
The reverse is also true (nvidia config set but BIOS configured to use iGPU only).
- If intel is set, it will load bbswitch module to set nvidia OFF.


## FAQ

### How do I select a driver ?

sudo prime-select `<driver>`

Where `<driver>` is one of:

- `intel`: use the `modesetting` driver
- `intel2`: use the `intel` driver (xf86-video-intel) 
- `nvidia`: use the NVIDIA proprietary driver
- `offload`: use PRIME Render Offload (possible with >= 435.xx driver)

Full command list available at `sudo prime-select`


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

### HDMI audio support does not work

Unfortunately HDMI audio support needs to be disabled in order to have DynamicPowerManagement for the NVIDIA GPU available. This is being done by default in the SUSE package. In order to reenable HDMI audio support (BUT: disable again DynamicPowerManagement at the same time!) you need to comment out all the lines in the file ` /usr/lib/udev/rules.d/90-nvidia-udev-pm-G05.rules`, i.e. all lines need to begin with a `#` sign.

In case you disabled HDMI audio support manually (i.e. probably not using a SUSE package) by following the section "NVIDIA power off support since 435.xxx driver with Turing GPU and later (G05 driver packages)" above you need to revert this step, i.e. remove again the file `/etc/udev/rules.d/90-nvidia-udev-pm-G05.rules`.

### Custom BOOT entries

When service is enabled, the script is capable to recognize following kernel parameters:

```
nvidia.prime=offload | nvidia.prime=intel | nvidia.prime=intel2 | nvidia.prime=nvidia
```

So is possible to have custom bootloader entries with all modes.

