# VFIO Single GPU Passthrough Configuration
My setup for passing a single GPU from my host OS to a Windows 10 virtual machine through kvm/qemu.

## 1. Introduction
There are plenty of VFIO passthrough guides for configurations utilizing multiple graphics e.g. integrated graphics + discrete graphics or dual discrete graphics cards. However, I found guides for a single GPU setup to be quite scarce. I wrote this mostly as notes to self but decided to turn it into some form of guide in case someone might benefit from it.

This solution hands over the GPU to guest OS upon booting the VM and hands it back to the host OS upon powering off the VM. The obvious downside of this is that you can't use the host OS (at least graphically) while the guest is running. It is therefore highly recommended that you set up SSH access to your host OS just in case of issues. If you do not and issues come up while booting your VM there is a high chance you will be locked out of your host.

This is by no means a comprehensive guide. It assumes you already know how to create a VM and won't walk you through these steps. [This tutorial by bryansteiner][bransteiner-git] covers this process extensively and I highly recommend you look at it if you need guidance at this stage. Specifically, [this section][actual-vm-setup] explains step-by-step what you should to in virt-manager.

Note that I am running an Nvidia card with the proprietary driver, and so some settings are specific to my case. The same principles also apply for AMD cards, although in this case there is also [this video by risingprismtv][youtube-amd].

#### Specifications
Here is my hardware and software configuration at the moment
##### Hardware
  - **CPU:** AMD Ryzen 5 1600 AF (6c/12t)
  - **GPU:** EVGA Nvidia 2060 KO 6GB GDDR6 Video Card
  - **RAM:** G.SKILL Ripjaws V Series 16GB (2x8GB) DDR4 3600MHz CL16
  - **Motherboard:** ASRock B450M Steel Legend Micro ATX
  - **SSD:** WD Blue 3D NAND 500GB M.2 SSD (SATA)
  - **HDD:** WD Blue 2TB 5400 RPM 256MB Cache SATA 6.0Gb/s 3.5" HDD
  - **PSU:** EVGA 600 BQ 80+ Bronze Semi Modular Power Supply

##### Software
  - **Host OS:** Arch Linux x86_64
  - **Kernel:** 5.8.7-zen1-1-zen
  - **qemu:** 5.1.0-1
  - **libvirt:** 6.5.0-1
  - **edk2-ovmf:** 202005-3
  - **Guest OS:** Windows 10 (Version 2004)

## 2. Configuration Settings
### 2.1: Host Machine Settings (Skip if you already have IOMMU enabled)
This section outlines settings you need to make on the host machine.

#### Enabling IOMMU in BIOS
[This article][main-wiki] is useful for explaining the beginning steps. As described, first enable IOMMU in your motherboard BIOS. Depending on your model and make the setting might be easy to find or a bit hidden. In my case with the ASRock B450M it was located at Advanced --> AMD CBS --> NBIO Common Options --> NB Configuration --> IOMMU. Toggling *Enabled* did the job for me.

#### Passing IOMMU & VFIO Parameters to Kernel
You then need to enable IOMMU support in the OS by passing the right parameters to kernel on boot. As per the wiki above, adding amd_iommu=on to kernel parameters should suffice for AMD CPUs. However, as per the recommendation of [this Level1Techs article][level1-article], I also passed the parameter rd.driver.pre=vfio-pci so as to load the VFIO driver at boot time. I also included parameter iommu=1. This may not be a necessary option, but I'm yet to test without it set. In the end these are the parameters that I ended up adding in /etc/default/grub:
```sh
GRUB_CMDLINE_LINUX_DEFAULT="... iommu=1 amd_iommu=on rd.driver.pre=vfio-pc ..."
```
#### Checking IOMMU Groups
Next is ensuring that the IOMMU groups are valid. On the wiki is a script to check how various PCI devices are mapped to IOMMU groups. The script is on this repository as check-iommu.sh. If the script doesn't return anything, you've either not enabled IOMMU support properly or your hardware does not support it. If you get output note the IOMMU group that your GPU is in. It is **very important** that you take note of all the physical devices in the same group as your GPU because you'll have to pass the entire set of devices to the VM. If you pass just a few it is highly likely that you will encounter errors on the VM. In my case this is the group with my graphics card:
```sh
...
IOMMU Group 13:
	06:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU104 [GeForce RTX 2060] [10de:1e89] (rev a1)
	06:00.1 Audio device [0403]: NVIDIA Corporation TU104 HD Audio Controller [10de:10f8] (rev a1)
	06:00.2 USB controller [0c03]: NVIDIA Corporation TU104 USB 3.1 Host Controller [10de:1ad8] (rev a1)
	06:00.3 Serial bus controller [0c80]: NVIDIA Corporation TU104 USB Type-C UCSI Controller [10de:1ad9] (rev a1)
...
```
I therefore must pass everything in group 13 together to the VM, that is, the VGA controller (GPU), audio controller, USB controller and serial bus controller. The set of devices vary between graphics card. Your setup will be similar to this is you are on Turing (RTX 20xx) but with Pascal (GTX 10xx) you will most likely have only the GPU and the audio controller. Whatever the case, take note of the bus addresses of all the devices within the same IOMMU group as your GPU (in this case 06:00.0 to 06:00.3).

## 2.2: Passthrough Settings
### Installing Hook Manager
We'll be utilizing [libvirt hooks][libvirt-hooks] to dynamically bind the vfio drivers right before the VM starts and then unbinding these drivers right after the VM terminates. To set this up we'll be following [this article from the Passthrough Post.][passthrough-post]

Scripts for libvirt-hooks should be located at /etc/libvirt/hooks. If the directory doesn't exist, go ahead and create it. Once done, install the hook manager and make it executable via the following commands:
```sh
$ sudo wget 'https://raw.githubusercontent.com/PassthroughPOST/VFIO-Tools/master/libvirt_hooks/qemu' \
     -O /etc/libvirt/hooks/qemu
$ sudo chmod +x /etc/libvirt/hooks/qemu
```
Restart the libvirtd service for libvirtd to recognize the hook manager.

Next, we are going to have subdirectories set up in the following structure under /etc/libvirt/hooks/qemu:
``` sh
$ tree /etc/libvirt/hooks/
/etc/libvirt/hooks/
├── qemu
└── qemu.d
    └── win10
        ├── prepare
        │   └── begin
        └── release
            └── end
```
The following are the functions for these directories
| Path | Purpose |
| ------ | ------ |
| /etc/libvirt/hooks/qemu.d/$vmname/prepare/begin/* | Resources in this folder are allocated before a VM is started |
| /etc/libvirt/hooks/qemu.d/$vmname/release/end/* | Resources in this folder are allocated after a VM has shut down |

Create the subdirectories above,remembering to use the name of your VM. In my case the VM name is win10, which is the default provided by virt-manager.

### Adding Hook Scripts
We are then going to put some scripts for allocating and deallocating the appropriate resources to our VM whenever it's started or shut down.

#### Set PCI IDs in Environment File
In /etc/libvirt/hooks/ create a file called kvm.conf and let it have content in the following format:
```sh
## Virsh devices
VIRSH_GPU_VIDEO=pci_0000_06_00_0
VIRSH_GPU_AUDIO=pci_0000_06_00_1
VIRSH_GPU_USB=pci_0000_06_00_2
VIRSH_GPU_SERIAL=pci_0000_06_00_3
```
Substitute the bus addresses for the devices you'd like to passthrough to your VM. This is where the addresses in step 1.3 (running check-iommu.sh) comes in. The prefix for the bus address (pci_0000) is fixed. The rest of the address should be the device IDs of the PCI devices notated using underscores i.e. 06:00.0 becomes 06_00_0, 06:00.1 becomes 06_00_1 etc.

#### Create Start Script
Create the file start.sh in /etc/libvirt/hooks/qemu.d/$vmname/prepare/begin/

```sh
#!/bin/bash
# Helpful to read output when debugging
set -x

# Load the config file with our environmental variables
source "/etc/libvirt/hooks/kvm.conf"

# Stop your display manager. If you're on kde it'll be sddm.service. Gnome users should use 'killall gdm-x-session' instead
systemctl stop lightdm.service

# Unbind VTconsoles
echo 0 > /sys/class/vtconsole/vtcon0/bind
# Some machines might have more than 1 virtual console. Add a line for each corresponding VTConsole
# echo 0 > /sys/class/vtconsole/vtcon1/bind

# Unbind EFI-Framebuffer
echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/unbind

# Avoid a race condition by waiting a couple of seconds. This can be calibrated to be shorter or longer if required for your system
sleep 5

# Unload all Nvidia drivers
modprobe -r nvidia_drm
modprobe -r nvidia_modeset
modprobe -r drm_kms_helper
modprobe -r nvidia
modprobe -r i2c_nvidia_gpu
modprobe -r drm

# Unbind the GPU from display driver
virsh nodedev-detach $VIRSH_GPU_VIDEO
virsh nodedev-detach $VIRSH_GPU_AUDIO
virsh nodedev-detach $VIRSH_GPU_USB
virsh nodedev-detach $VIRSH_GPU_SERIAL

# Load VFIO kernel module
modprobe vfio
modprobe vfio_pci
modprobe vfio_iommu_type1
```
You may not need to unload as many nvidia drivers as I have. For example, in your case the drivers might simply be nvidia_drm, nvidia_modeset, nvidia_uvm, nvidia. Run the following command to be sure which drivers to unload:
```sh
$ lsmod | grep nvidia
```

#### Create Revert Script
Create the file revert.sh in /etc/libvirt/hooks/qemu.d/$vmname/release/end
```sh
#!/bin/bash
set -x

# Load the config file with our environmental variables
source "/etc/libvirt/hooks/kvm.conf"

# Unload VFIO-PCI Kernel Driver
modprobe -r vfio_pci
modprobe -r vfio_iommu_type1
modprobe -r vfio

# Re-Bind GPU to our display drivers
virsh nodedev-reattach $VIRSH_GPU_VIDEO
virsh nodedev-reattach $VIRSH_GPU_AUDIO
virsh nodedev-reattach $VIRSH_GPU_USB
virsh nodedev-reattach $VIRSH_GPU_SERIAL

# Rebind VT consoles
echo 1 > /sys/class/vtconsole/vtcon0/bind
# echo 0 > /sys/class/vtconsole/vtcon1/bind

# Read our nvidia configuration when before starting our graphics
nvidia-xconfig --query-gpu-info > /dev/null 2>&1

# Re-Bind EFI-Framebuffer
echo "efi-framebuffer.0" > /sys/bus/platform/drivers/efi-framebuffer/bind

# Load nvidia drivers
modprobe nvidia_drm
modprobe nvidia_modeset
modprobe drm_kms_helper
modprobe nvidia
modprobe i2c_nvidia_gpu
modprobe drm

# Restart Display Manager
systemctl start lightdm.service
```
## 3. Run the VM
Start the VM. The hook scripts defined above should automatically run. Your display should stay black/blank for a while then log into your VM as if you dual booted into it.

If you are stuck on the black screen without logging into the guest OS monitor the logs at /var/log/libvirt/qemu/$vm_name.log. [This][nvidia-single-gpu-passthrough] may help you troubleshoot your issues as well.


[//]: # (These are reference links used in the body of this note and get stripped out when the markdown processor does its job. There is no need to format nicely because it shouldn't be seen. Thanks SO - http://stackoverflow.com/questions/4823468/store-comments-in-markdown-syntax)

   [youtube-amd]: <https://www.youtube.com/watch?v=3BxAaaRDEEw>
   [main-wiki]: <https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF#Enabling_IOMMU>
   [level1-article]: <https://level1techs.com/article/ryzen-gpu-passthrough-setup-guide-fedora-26-windows-gaming-linux>
   [bransteiner-git]: <https://github.com/bryansteiner/gpu-passthrough-tutorial>
   [libvirt-hooks]: <https://libvirt.org/hooks.html>
   [passthrough-post]: <https://passthroughpo.st/simple-per-vm-libvirt-hooks-with-the-vfio-tools-hook-helper/>
   [actual-vm-setup]: <https://github.com/bryansteiner/gpu-passthrough-tutorial#----part-3-creating-the-vm>
   [nvidia-single-gpu-passthrough]: <https://github.com/joeknock90/Single-GPU-Passthrough#black-screen-on-vm-activation>

