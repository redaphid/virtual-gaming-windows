# VFIO Single GPU Passthrough Configuration
My setup for passing a single GPU from my host OS to a Windows 10 virtual machine through kvm/qemu.

## 1. Introduction
There are plenty of VFIO passthrough guides for configurations utilizing multiple graphics e.g. integrated graphics + discrete graphics or dual discrete graphics cards. However, I found guides for a single GPU setup to be quite scarce. I wrote this mostly as notes to self but decided to turn it into some form of guide in case someone might benefit from it.

This solution basically hands over the GPU to guest OS upon booting the VM and hands it back to the host OS upon powering off the VM. The obvious downside of this is that you can't use the host OS (at least graphically) while the guest is running. It is therefore highly recommended that you set up SSH access to your host OS just in case of issues. 

Note that this is by no means a beginner's guide. It makes the following assumptions:
1. You have hardware that supports virtualization and IOMMU.
2. You have the necessary packages for virtualizing using kvm/qemu. 
3. You have a working/running VM on kvm/qemu (or you at least know how to set one up).

It therefore won't walk you through the basic steps of creating the VM itself. However, [this tutorial by bryansteiner][bransteiner-git] covers this process adequately. I highly recommend you look at it if you need that kind of guidance. Specifically, [this section][actual-vm-setup] explains step-by-step what you should to in virt-manager.

Note that I am running an Nvidia card with the proprietary driver, and so some settings are specific to my case e.g. GPU drivers. The same principles also apply for AMD cards, although in this case there is also [this video by risingprismtv][youtube-amd].

#### Specifications

##### Hardware
  - **CPU:** AMD Ryzen 5 1600 AF (YD1600BBAFBOX) 6c/12t 3.2GHz/3.6GHz
  - **GPU:** EVGA Nvidia 2060 KO 6GB GDDR6
  - **RAM:** G.SKILL Ripjaws V Series 16GB (2x8GB) DDR4 3600MHz CL16
  - **Motherboard:** ASRock B450M Steel Legend Micro ATX
  - **SSD:** WD Blue 3D NAND 500GB M.2 SSD (SATA)
  - **HDD:** WD Blue 2TB 5400 RPM 256MB Cache SATA 6.0Gb/s 3.5" HDD
  - **PSU:** EVGA 600 BQ 80+ Bronze Semi Modular Power Supply

##### Software
  - **BIOS/UEFI Info:** 
    * BIOS Version P2.90 (2019/11/28) 
    * AGESA Combo-AM4 1.0.0.4
    * Revision 5.14
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
[This arch wiki page][main-wiki] does a good job explaining the process of enabing IOMMU. As described, first enable IOMMU in your motherboard BIOS. The location varies with the model/make of the motherboard. In my case with the ASRock B450M the setting was at Advanced --> AMD CBS --> NBIO Common Options --> NB Configuration --> IOMMU.

#### Passing IOMMU & VFIO Parameters to Kernel
As per the aforementioned wiki, adding amd_iommu=on to kernel parameters should suffice for AMD CPUs. However, as per the recommendation of [this Level1Techs article][level1-article], I also passed the parameter rd.driver.pre=vfio-pci so as to load the VFIO driver at boot time. I also included parameter iommu=1. This may not be a necessary option, but I'm yet to test without it set. In the end these are the parameters that I ended up adding to my boot parameters in /etc/default/grub:
```sh
GRUB_CMDLINE_LINUX_DEFAULT="... iommu=1 amd_iommu=on rd.driver.pre=vfio-pc ..."
```
#### Checking IOMMU Groups
If the conditions above are met, the next step is ensuring that we have some sane IOMMU groups.This is checking how various PCI devices are mapped to IOMMU groups. Run the script [check-iommu.sh](https://gitlab.com/Karuri/vfio/-/blob/master/check-iommu.sh) for this. 

If the script doesn't return anything, you've either not enabled IOMMU support properly or your hardware does not support it. If you get output note the IOMMU group that your GPU is in. It's important that you take note of *all* the physical devices in the same group as your GPU because **you'll have to pass the entire set of devices to the VM.** In my case this is the group with my graphics card:
```sh
...
IOMMU Group 13:
  06:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU104 [GeForce RTX 2060] [10de:1e89] (rev a1)
  06:00.1 Audio device [0403]: NVIDIA Corporation TU104 HD Audio Controller [10de:10f8] (rev a1)
  06:00.2 USB controller [0c03]: NVIDIA Corporation TU104 USB 3.1 Host Controller [10de:1ad8] (rev a1)
  06:00.3 Serial bus controller [0c80]: NVIDIA Corporation TU104 USB Type-C UCSI Controller [10de:1ad9] (rev a1)
...
```
I therefore must pass everything in IOMMU group 13 together to the VM i.e. the VGA controller (GPU), audio controller, USB controller and serial bus controller. The set of devices vary between graphics card. The typical scenario is usually two devices (GPU and audio controller) but more recent graphics card have more devices. Whatever your case us, take note of the bus addresses of all the devices within the same IOMMU group as your GPU. For me the bus addresses are 06:00.0 to 06:00.3.

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

Create the subdirectories above,remembering to use the name of your VM. In my case the VM name is win10, which is the default provided by virt-manager for Windows 10.

### Adding Hook Scripts
We are then going to put some scripts for allocating and deallocating the appropriate resources to our VM whenever it's started or shut down. The first script is just for holding the environmental variables that we'll be using in the actual scripts. This should prevent us from unnecessarily duplicating information and also make it easier for us to make adjustments down the line. 

##### Creating our Environment File
In /etc/libvirt/hooks/ create a file called kvm.conf and let it have content in the following format:
```sh
## Virsh devices
VIRSH_GPU_VIDEO=pci_0000_06_00_0
VIRSH_GPU_AUDIO=pci_0000_06_00_1
VIRSH_GPU_USB=pci_0000_06_00_2
VIRSH_GPU_SERIAL=pci_0000_06_00_3
```
Substitute the bus addresses for the devices in your GPU's IOMMU group. These are the addresses you get from running [check-iommu.sh](https://gitlab.com/Karuri/vfio/-/blob/master/check-iommu.sh). Note the format we are using for the bus addresses. The prefix for the bus address (pci_0000...) is fixed. The rest of the address should be the device IDs of the PCI devices notated using underscores i.e. 06:00.0 becomes 06_00_0, 06:00.1 becomes 06_00_1 etc.

#### Creating Start Script
Create the file **start.sh** at /etc/libvirt/hooks/qemu.d/$vmname/prepare/begin/

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
You may not need to unload as many nvidia drivers as I have. For example, in your case the drivers might simply be nvidia_drm, nvidia_modeset, nvidia_uvm, nvidia. If unsure, use *lsmod* to check what drivers are currently in use on your host OS e.g.
```sh
$ lsmod | grep -i nvidia
```

#### Create Revert Script
Create the file **revert.sh** at /etc/libvirt/hooks/qemu.d/$vmname/release/end
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
## Run VM
Start the VM. The hook scripts defined above will be executed automatically as the guest OS starts. If things go well your display should turn black for a couple of seconds, then display the guest OS on your screen as if you dual booted into it.

If you instead get stuck on the black screen without logging into the guest OS monitor the logs for the VM at /var/log/libvirt/qemu/$vm_name.log (on the host OS). This is where SSH access to your host comes in handy. An important step in your troubleshooting should be executing the hook scripts (start.sh and revert.sh) manually. Check for errors. [This guide by joeknock90][nvidia-single-gpu-passthrough] may be of assistance as you troubleshoot your issues.

## Additional Hook Scripts
 I have additional hook scripts for optimization/performance reasons.
 
#### Huge Pages
 I use huge pages to reduce memory latency. Your distro may already have huge enabled out of the box or need installation. If you're running kvm/qemu on arch or an arch-based distro the feature is already enabled. However, there are still [some additional steps][wiki-hugepages] you'll need to take. For other distros ensure to follow the appropriate steps to enable huge pages on your host OS.
 
 Once the huge pages are set up, add the parameter *MEMORY* to [/etc/libvirt/hooks/kvm.conf](https://gitlab.com/Karuri/vfio/-/blob/master/alloc_hugepages.sh). The value for this parameter should be the amount of RAM, in megabytes, that you have assigned to your VM. In my case I have 12 GB (12888 MB) allocated to the Windows 10 guest OS. You'll also need to add a configuration optionn to your VM's XML to tell it to use hugepages. Right after the settings for the memory, insert the memoryBacking lines so that your configuration looks like this:
 ```sh
   ...
   <!-- options memory unit and currentMemory are for the RAM currerty assigned to the VM. Add memoryBacking like below -->
   <memory unit="KiB">12582912</memory>
   <currentMemory unit="KiB">12582912</currentMemory>
   <memoryBacking>
     <hugepages/>
   </memoryBacking>
   ...
 ```
 Next, add [alloc_hugepages.sh](https://gitlab.com/Karuri/vfio/-/blob/master/alloc_hugepages.sh) to /etc/libvirt/hooks/qemu.d/win10/prepare/begin and [dealloc_hugepages.sh](https://gitlab.com/Karuri/vfio/-/blob/master/dealloc_hugepages.sh) to /etc/libvirt/hooks/qemu.d/win10/release/end. The first script allocates huge pages to your VM whenever it boots and the second script deallocates hugepages when the VM stops/powers off. This is an elegant solution because you only have the huge pages up when your VM needs them. 
 
 To test if the allocation happened successfully, run the following command after the VM is powered on:
 ```sh
 $ grep HugePages_Total /proc/meminfo
 ````
 This should print out the amount of huge pages reserved on the host OS. Output from my configuration looks like this:
 ```sh
 HugePages_Total:    6144
 ```
#### CPU Governor Scripts
By default CPU governor settings are set to mode "on demand", where CPUs boost behaviour is based on the load. This goes a long way in saving power in typical use cases but is bad in the case of a guest OS. Due to the amount of abstraction done in the virtualization proces the guest OS only works with virtual cores assigned it. It therefore can't demand for more *juice* from the host.

The script [cpu_mode_performance.sh](https://gitlab.com/Karuri/vfio/-/blob/master/cpu_mode_performance.sh) set the CPU on the host to "performance" mode whenever the VM is started. Add it to /etc/libvirt/hooks/qemu.d/win10/prepare/begin. 

The script [cpu_mode_ondemand.sh](https://gitlab.com/Karuri/vfio/-/blob/master/cpu_mode_ondemand.sh) reverts the CPUs on the host back to "on demand" wheneverthe VM is powered off. Add it to /etc/libvirt/hooks/qemu.d/win10/release/end.

While the VM is running you can confirm that the host's CPU is on "performance" mode by running the following command:
```sh
$ cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
```
The output should be the mode the CPU is running on i.e. "performance".

 ## VM Optimization Tweaks/Settings
 These are additional settings on the VM for performance improvement. They are all available on [win10.xml](https://gitlab.com/Karuri/vfio/-/blob/master/win10.xml).

#### CPU Pinning
CPU pinning is an important step in optimizing CPU performance for VMs on multithreaded CPUs.

The rule of the thumb is to pass to the virtual machine cores that are as close to each other as possible so as to minimize latency. When you passthrough a core you typically want to include its sibling. There isn't a one-size-fits-all solution here since the topology varies from CPU to CPU. You should **NOT** copy-paste a solution you found somewhere (this included) and then use it for your setup. The package *hwloc* can visually show you the topology of your CPU and go a long way in aiding you choose the right cores to pin. Simply run the following command once you have the pacakage installed
```sh
$ lstopo
```
This is the topology for my CPU:
[![2020-09-10-02-27.png](https://i.postimg.cc/T35z2v38/2020-09-10-02-27.png)](https://postimg.cc/75DsXczX)

To explain a little bit, I have 6 physical cores (Core L#0 to L#5) and 12 virtual cores (PU L#0 to PU L#11). The 6 physical cores are majorly split into groups of 3, each group sharing L3 (level 3) cache. The groups are core L#0 to L#2 and core L#3 to L#5. Each pair of virtual cores within the physical one are the *siblings* e.g. 
- PU L#0 and PU L#1
- PU L#2 and PU L#3
- PU L#6 and PU L#7

For my setup I'm passing through 4 physical cores (8 virtual cores). Following the topology of my CPU I decided to allocate all the virtual cores on the left side and one pair from the right. If instead I had a 8c/16t processor with the cores split 4-4 instead I would allocate the cores on one side only and not have to deal with the latency penalty of jumping from CCX to CCX. This would also have been the case if I was only passing through 3c/6t. Read more on CPU pinning [here](https://github.com/bryansteiner/gpu-passthrough-tutorial#----cpu-pinning).

Here is my CPU pinning setup:
```
  ...
  <vcpu placement="static">8</vcpu>
  <iothreads>4</iothreads>
  <cputune>
    <vcpupin vcpu="0" cpuset="0"/>
    <vcpupin vcpu="1" cpuset="1"/>
    <vcpupin vcpu="2" cpuset="2"/>
    <vcpupin vcpu="3" cpuset="3"/>
    <vcpupin vcpu="4" cpuset="4"/>
    <vcpupin vcpu="5" cpuset="5"/>
    <vcpupin vcpu="6" cpuset="6"/>
    <vcpupin vcpu="7" cpuset="7"/>
    <emulatorpin cpuset="0,3"/>
    <iothreadpin iothread="1" cpuset="0-1"/>
    <iothreadpin iothread="2" cpuset="2-3"/>
    <iothreadpin iothread="3" cpuset="4-5"/>
    <iothreadpin iothread="4" cpuset="6-7"/>
  </cputune>
  ...
```
The *iothreads* element specifies the number of threads dedicated to performing block I/O. More information on this [here](https://libvirt.org/formatdomain.html#iothreads-allocation). This means that the other threads assigned to your VM can focus on handling whatever other tasks you are throwing at them instead of bothering themselves with I/O operations. The *iothreadpin* element specifies which of host physical CPUs the IOThreads will be pinned to. 

#### Better SMT Performance (for AMD Ryzen CPUs)
This is the configuration of the CPU for enabling SMT on the guest OS. This [should improve performance for AMD Ryzen CPUs](https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF#Improving_performance_on_AMD_CPUs):
```sh
  <cpu mode="host-passthrough" check="none" migratable="on">
    <topology sockets="1" dies="1" cores="4" threads="2"/>
    <cache mode="passthrough"/>
    <feature policy="require" name="topoext"/>
  </cpu>

```
#### Disk Performance Tuning using virtio-blk/virtio-scsi
[This post](https://mpolednik.github.io/2017/01/23/virtio-blk-vs-virtio-scsi/) explains the benefits of using either virtio-blk or virtio-scsi. I'm using virtio-blk for my emulated storage device. Using an actual physical disk should offer a way better experience than using emulated storage. I intend to get an extra SSD for this very purpose, but for now this does it: 
```
    <disk type="file" device="disk">
      <driver name="qemu" type="qcow2"/>
      <source file="/media/HardDrive/VMs/win10.qcow2"/>
      <target dev="vda" bus="virtio"/>
      <boot order="1"/>
      <address type="pci" domain="0x0000" bus="0x06" slot="0x00" function="0x0"/>
    </disk>
```

#### Hyper-V Enlightenments
I'm utilizing the following Hyper-V enlightments help the Guest OS handle the virtualization tasks. Documentation for what each feature does can be found [here](https://libvirt.org/formatdomain.html#elementsFeatures).
```
    ...
    <hyperv>
      <relaxed state="on"/>
      <vapic state="on"/>
      <spinlocks state="on" retries="8191"/>
      <vpindex state="on"/>
      <synic state="on"/>
      <stimer state="on"/>
      <reset state="on"/>
      <vendor_id state="on" value="whatever_value"/>
      <frequencies state="on"/>
    </hyperv>
    <kvm>
      <hidden state="on"/>
    </kvm>
    ...
```
The *vendor_id* setting is for going around [the infamous Error 43 error on Nvidia GPUs](https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF#%22Error_43:_Driver_failed_to_load%22_on_Nvidia_GPUs_passed_to_Windows_VMs). However, it may also fix some issues with AMD Radeon drivers from version 20.5.1 onwards. The purpose of the *kvm* section (right after the *hyperv* section) is to instruct the kvm to hide its state basically to cheat the guest OS into "thinking" it's on non-virtualized hardware. 

[//]: # (References)
   [youtube-amd]: <https://www.youtube.com/watch?v=3BxAaaRDEEw>
   [main-wiki]: <https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF#Enabling_IOMMU>
   [level1-article]: <https://level1techs.com/article/ryzen-gpu-passthrough-setup-guide-fedora-26-windows-gaming-linux>
   [bransteiner-git]: <https://github.com/bryansteiner/gpu-passthrough-tutorial>
   [libvirt-hooks]: <https://libvirt.org/hooks.html>
   [passthrough-post]: <https://passthroughpo.st/simple-per-vm-libvirt-hooks-with-the-vfio-tools-hook-helper/>
   [actual-vm-setup]: <https://github.com/bryansteiner/gpu-passthrough-tutorial#----part-3-creating-the-vm>
   [nvidia-single-gpu-passthrough]: <https://github.com/joeknock90/Single-GPU-Passthrough#black-screen-on-vm-activation>
   [wiki-hugepages]:<https://wiki.archlinux.org/index.php/KVM#Enabling_huge_pages>

