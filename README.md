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
For Intel CPUs passing intel_iommu=on should suffice.

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

Note that the IOMMU group of your GPU should only contain devices connected to the GPU. If there is an unrelated device you'll have to figure out a way to split it into its own IOMMU groups. An [ACS override patch](https://queuecumber.gitlab.io/linux-acs-override/) will be necessary for this. Visit [this link](https://github.com/bryansteiner/gpu-passthrough-tutorial#----acs-override-patch-optional) for more information.

## 2.2: Virtual Machine Settings
As noted earlier, this guide shall not cover how create a kvm/qemu VM. Refer to [this guide](https://github.com/bryansteiner/gpu-passthrough-tutorial#----part-3-creating-the-vm) for these steps. However, there a few things you should pay attention to:

**1. Use UEFI-enabled firmware for the VM:** 
If using virt-manager you can check this under Overview --> Hypervisor Details --> Firmware. Choose UEFI x86_64: /usr/share/OVMF/OVMF_CODE.fd if available.
**2. Pass the GPU and related devices:**
If using virt-manager, click 'Add Hardware' and under 'PCI Host Device' select the bus ID of your GPU. Do the same for all the devices associated with your GPU (all the devices in the same IOMMU group as the GPU).
**3. Patch NVIDIA BIOS (only for Pascal GPUs):**
For Nvidia Pascal owners (GTX 10xx) you'll need to patch the GPU BIOS before the virtual machine can recognize it. To do so you'll first need the ROM for your GPU, which you can obtain in one of two ways:
a. Dumping your current BIOS using a tool like [Nvidia nvflash](https://www.techpowerup.com/download/nvidia-nvflash/); or
b. Downloading a user-submitted BIOS for your GPU model from [TechPowerUp](https://www.techpowerup.com/vgabios/).

Next, clone the [NVIDIA vBIOS VFIO Patcher tool](https://github.com/Matoking/NVIDIA-vBIOS-VFIO-Patcher). The most important file here is *nvidia_vbios_vfio_patcher.py*. To create a patched BIOS for your Pascal GPU simply run the following command:
```sh
$ python nvidia_vbios_vfio_patcher.py -i <ORIGINAL_ROM> -o <PATCHED_ROM>
```
Where <ORIGINAL_ROM> is the original BIOS for your GPU and <PATCHED_ROM> is the patched ROM. They should of course be having different names. Finally, pass the patched copy of the vBIOS to libvirt so that the NVIDIA GPU can be used in the guest VM. Do so by adding the following line to the VM domain XML file.
```
   <hostdev>
     ...
     <rom file='/path/to/your/patched/gpu/bios.bin'/>
     ...
   </hostdev>
```
If you don't know how to access the VM's XML do so by going to Overview and opening the XML tab. To edit the XML you must go to Edit --> Preferences --> General and check "Enable XML Settings". If you instead prefer using a terminal editor run the following command:
```sh
$ sudo virsh edit win10
```
**4. Pass physical disk (if you have Windows 10 installed on a physical disk):**
If you already have Windows 10 installed on a physical/raw media device you'll need to instruct the VM to use the physical disk instead of emulated storage. This involves editing the VM's XML in the *disk* section from:
```
...
<disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' cache='none'/>
      <source file='/path/to/disk/image.qcow2'/>
      <target dev='sda' bus='sata'/>
      <address type='drive' controller='0' bus='0' target='0' unit='0'/>
 </disk>
 ...
```
To:
```
...
<disk type='block' device='disk'>
      <driver name='qemu' type='raw' />
      <source dev='/dev/sda'/>
      <target dev='vdb' bus='virtio'/>
      <address type='drive' controller='0' bus='0' target='0' unit='0'/>
 </disk>
 ...
```
You should of course change */dev/sda* to the correct path to your storage device.

## 2.3: Passthrough Settings
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

### CPU Pinning
CPU pinning is an important step in optimizing CPU performance for VMs on multithreaded CPUs.

The rule of the thumb is to pass to the virtual machine cores that are as close to each other as possible so as to minimize latency. When you passthrough a virtual core you typically want to include its sibling. There isn't a one-size-fits-all solution here since the topology varies from CPU to CPU. You should therefore **NOT** copy a solution you found somewhere (mine included) and then just use it for your setup. 

There are two tools that can assist you in choosing the right cores to map. One is a quick solution that will generate a configuration for you to use and the other gives you information to enable you to pick a sensible configuration for yourself. 

#### Tool 1: CPU Pinning Helper (quick, autogenerates config for you)
The CPU Pinning Helper will choose the right cores for you pretty quick. They have a web tool you can use from the browser and an API you can use from terminal.

##### API Method
To use the API simply run the following command, substituting *$CORES* with the number of cores you've assigned your vm:
```sh
$ curl -X POST -F "vcpu=$CORES" -F "lscpu=`lscpu -p`" https://passthroughtools.org/api/v1/cpupin/
```
I'm assigning mine 8 cores, so this is my command:
```sh
$ curl -X POST -F "vcpu=8" -F "lscpu=`lscpu -p`" https://passthroughtools.org/api/v1/cpupin/
```
##### Web Method
Open their web tool by visiting [this link](https://passthroughtools.org/cpupin/). In the first field enter the number of cores you'll be assigning the VM. In the text box below it paste the output of running "lscpu -p" on your host machine. Click **Submit** to have an optimal pinning configuration generated for you.
[![2020-09-12-20-25.png](https://i.postimg.cc/pXZ3FQJm/2020-09-12-20-25.png)](https://postimg.cc/RNWPrH8m)

Both methods should produce the same results. This is the configuration generated for my setup:
```
  <vcpu placement='static'>8</vcpu>
  <cputune>
    <vcpupin vcpu='0' cpuset='2'/>
    <vcpupin vcpu='1' cpuset='8'/>
    <vcpupin vcpu='2' cpuset='3'/>
    <vcpupin vcpu='3' cpuset='9'/>
    <vcpupin vcpu='4' cpuset='4'/>
    <vcpupin vcpu='5' cpuset='10'/>
    <vcpupin vcpu='6' cpuset='5'/>
    <vcpupin vcpu='7' cpuset='11'/>
  </cputune>
  <cpu mode='host-passthrough' check='none'>
    <topology sockets='1' cores='4' threads='2'/>
    <cache mode='passthrough'/>
  </cpu>
```
Copy the configuration and add it to your VM's XML file. That is it.I recommend you still go through the second tool for a more in-depth understanding of what is going on here. However, you don't have to :-)

#### Tool 2: hwloc (for a more in-depth understanding)
The package *hwloc* can visually show you the topology of your CPU. Run the following command once you've installed it:
```sh
$ lstopo
```
This is the topology for my CPU as produced by the command above:
[![2020-09-10-02-27.png](https://i.postimg.cc/T35z2v38/2020-09-10-02-27.png)](https://postimg.cc/75DsXczX)
The format above can be a bit confusing due to the default display mode of the indexes. Toggle the display mode using **i** until the legend (at the bottom) shows "Indexes: Physical". The layout should become more clear. In my case it becomes this:
[![2020-09-12-17-25.png](https://i.postimg.cc/bNR7T5Zp/2020-09-12-17-25.png)](https://postimg.cc/WhhYpXmH)

To explain a little bit, I have 6 physical cores (Core P#0 to P#6) and 12 virtual cores (PU P#0 to PU P#11). The 6 physical cores are mainly divided into two sets of 3 cores: Core P#0 to P#2; and Core P#4 to P#6. Each group has its own L3 cache. However, the most important thing to pay attention here is how virtual cores are mapped to the physical core. The virtual cores (notated PU P#...) come in pairs of two i.e. *siblings*: 
- PU P#0 and PU P#6 are siblings in Core P#0
- PU P#1 and PU P#7 are siblings in Core P#1
- PU P#2 and PU P#8 are siblings in Core P#3

When pinning CPUs you should map siblings that are adjacent to each other. Lets check what cores the CPU Pinning Helper (above) decided to pin. 
[![2020-09-12-20-57.png](https://i.postimg.cc/ZYH5TMDg/2020-09-12-20-57.png)](https://postimg.cc/MXcS5dwb)

It chose all the cores on the right and a pair from the left. The pair on the left that it chose are the cores most adjacent to the cores on the right.I could, however, decide to allocate all the cores on the left side and a pair from the right which is most adjacent left-side cores:
[![2020-09-12-21-01.png](https://i.postimg.cc/zfYyLRwP/2020-09-12-21-01.png)](https://postimg.cc/0zZkFjBp)

Here is the pinning  based on my "left-to-right" configuration as opposed to the Pinning Helper's "right-to-left":
```
  <vcpu placement="static">8</vcpu>
  <cputune>
    <vcpupin vcpu="0" cpuset="0"/>
    <vcpupin vcpu="1" cpuset="6"/>
    <vcpupin vcpu="2" cpuset="1"/>
    <vcpupin vcpu="3" cpuset="7"/>
    <vcpupin vcpu="4" cpuset="2"/>
    <vcpupin vcpu="5" cpuset="8"/>
    <vcpupin vcpu="6" cpuset="3"/>
    <vcpupin vcpu="7" cpuset="9"/>
  </cputune>
  <cpu mode='host-passthrough' check='none'>
    <topology sockets='1' cores='4' threads='2'/>
    <cache mode='passthrough'/>
  </cpu>
```
Hopefully now you have a clear understanding of the methodology behind CPU pinning. 

#### Iothreads and Iothreadpins
I build upon CPU pinning using IOthreads and IOthreadpins. According to [documentation](https://libvirt.org/formatdomain.html#iothreads-allocation):
- *iothreads* specifies the number of threads dedicated to performing block I/O.
- *iothreadpin* specifies which of host physical CPUs the IOThreads will be pinned to. 
- *emulatorpin* specifies which of host physical CPUs the "emulator" will be pinned to. 

The Arch Wiki recommends to pin the emulator and iothreads to host cores (if available) rather than the cores assigned to the virtual machine. If you do not intend to be doing any computation-heavy work on the host (or even anything at all) at the same time as you would on the VM, you can to pin your VM threads across all of your cores so that the VM can fully take advantage of the spare CPU time the host has available. However pinning all physical and logical cores of your CPU can potentially induce latency in the guest VM.

For my CPU, which has a total of 12 virtual cores,  8 are already assigned to the guest. Since for my use case I use host for nothing while the guest is running, I decided to use the rest of the 4 remaining cores to for Iothread pinning. If for your use case you'll still be using the host for something else do not exhaust your cores! 


Before the *cputune* element add an *iothreads* element. Inside the *cpuelement* body, allocate threadpins for each *iothread* you have defined . Here is my configuration for this:
```
  <vcpu placement="static">8</vcpu>
  <iothreads>2</iothreads>
  <cputune>
    <vcpupin vcpu="0" cpuset="0"/>
    <vcpupin vcpu="1" cpuset="6"/>
    <vcpupin vcpu="2" cpuset="1"/>
    <vcpupin vcpu="3" cpuset="7"/>
    <vcpupin vcpu="4" cpuset="2"/>
    <vcpupin vcpu="5" cpuset="8"/>
    <vcpupin vcpu="6" cpuset="3"/>
    <vcpupin vcpu="7" cpuset="9"/>
    <emulatorpin cpuset='5-6'/>
    <iothreadpin iothread="1" cpuset="4-10"/>
    <iothreadpin iothread="2" cpuset="5-11"/>
  </cputune>
  <cpu mode='host-passthrough' check='none'>
    <topology sockets='1' cores='4' threads='2'/>
    <cache mode='passthrough'/>
  </cpu>
```
Be careful with this section as you can easily hurt your guest's performance. A safe bet would be not to exhaust your cores. You can read more on this [here](https://mathiashueber.com/performance-tweaks-gaming-on-virtual-machines/).

#### Better SMT Performance (for AMD Ryzen CPUs)
This is the configuration of the CPU for enabling SMT on the guest OS. This [should improve performance for AMD Ryzen CPUs](https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF#Improving_performance_on_AMD_CPUs). To enable this, simply add the following line inside the *cpu* settings: 
```
   ...
   <feature policy="require" name="topoext"/>
   ...
```
This is how the *cpu* looks after adding the line
```
  <cpu mode="host-passthrough" check="none" >
    <topology sockets="1" cores="4" threads="2"/>
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

## Credits:
1. The Arch Wiki for instructions on [how to enable PCI passthrough via OVMF](https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF).
2. Wendell from Level1Techs for [the Ryzen GPU Passthrough Setup Guide](https://level1techs.com/article/ryzen-gpu-passthrough-setup-guide-fedora-26-windows-gaming-linux).
3. Bryansteiner (GitHub) for the [GPU passthrough tutorial](https://github.com/bryansteiner/gpu-passthrough-tutorial#considerations).
4. Joeknock90 (Github) for the [single GPU passthrough tutorial](https://github.com/joeknock90/Single-GPU-Passthrough)
5. Mathias Hueber (MathiasHueber.com) for [tips on performance tuning](https://mathiashueber.com/performance-tweaks-gaming-on-virtual-machines/).
6. Risingprismtv (YouTube) for his [video guide on single GPU passthrough for AMD GPUs](https://www.youtube.com/watch?v=3BxAaaRDEEw).
7. Matoking (GitHub) for the [NVIDIA vBIOS Patcher tool](https://github.com/Matoking/NVIDIA-vBIOS-VFIO-Patcher).
8. Reddit user *jibbyjobo* for pointing me to the [CPU Pinning Helper](https://passthroughtools.org/cpupin/).

### Enquiries:
If you need help on this subject matter feel free to reach me on Reddit, username *Danc1ngRasta*. Make sure to follow what is the guide exhaustively before reaching out. 

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

