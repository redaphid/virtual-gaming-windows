# CPU

| Config |  Max Threads | 1 Thread | 2 Threads | 4 Threads | 8 Threads | 16 Threads |
|--------|--------------|----------|-----------|-----------|-----------|------------|
|  1     |  4378        | 666      | 1312      | 2560      | 4731      | 4734       |
|  2     |  7280        | 660      | 1296      | 2561      | 4626      | 7656       |
|  3     |  8051        | 663      | 1313      | 2575      | 4817      | 8051       |
|  4     |  7110        | 660      | 1301      | 2554      | 4477      | 7025       |
|  5     |  8228        | 661      | 1333      | 2642      | 4835      | 8278       |
|  5     |  8904        | 666      | 1328      | 2610      | 4779      | 8904       |

## 1 - Original CPU Topology
```xml
  <cpu mode='host-passthrough' check='none' migratable='on'>
    <topology sockets='2' dies='1' cores='8' threads='1'/>
    <feature policy='disable' name='smep'/>
    <feature policy='disable' name='hypervisor'/>
  </cpu>
```
## 2 - New CPU Topology
```xml
  <cpu mode="host-passthrough" check="none" migratable="on">
    <topology sockets="1" dies="1" cores="8" threads="2"/>
    <feature policy="disable" name="smep"/>
    <feature policy="disable" name="hypervisor"/>
  </cpu>
```
## 3 - [CPU Governor](https://mathiashueber.com/performance-tweaks-gaming-on-virtual-machines#ib-toc-anchor-5)
```bash
#!/usr/bin/env fish
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
for file in (ls /sys/devices/system/cpu/*/cpufreq/scaling_governor)
  echo  "performance" > $file
end
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

~~## 4 - [topoext](https://mathiashueber.com/performance-tweaks-gaming-on-virtual-machines#ib-toc-anchor-9)~~

## 5 [CPU Pinning](https://mathiashueber.com/performance-tweaks-gaming-on-virtual-machines#ib-toc-anchor-8)
```xml
  <domain type='kvm' xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0'>
  <!-- later, in the <vcpu> element -->
<vcpu placement='static'>8</vcpu>
<iothreads>2</iothreads>
<cputune>
    <vcpupin vcpu='0' cpuset='8'/>
    <vcpupin vcpu='1' cpuset='9'/>
    <vcpupin vcpu='2' cpuset='10'/>
    <vcpupin vcpu='3' cpuset='11'/>
    <vcpupin vcpu='4' cpuset='12'/>
    <vcpupin vcpu='5' cpuset='13'/>
    <vcpupin vcpu='6' cpuset='14'/>
    <vcpupin vcpu='7' cpuset='15'/>
    <emulatorpin cpuset='0-1'/>
    <iothreadpin iothread='1' cpuset='0-1'/>
    <iothreadpin iothread='2' cpuset='2-3'/>
 </cputune>
```

## 6 [CPU Cache Passthrough](https://mathiashueber.com/performance-tweaks-gaming-on-virtual-machines#ib-toc-anchor-10)
```xml
  <cpu mode='host-passthrough' check='none' migratable='on'>
    <cache mode='passthrough'/>
  </cpu>
```
## 7 [Re-Enable Hyperthreading](https://www.reddit.com/r/VFIO/comments/sp2n2a/poor_gaming_performance_with_low_gpu_usage/)
### REMOVE THIS LINE:
```xml
<feature policy="disable" name="hypervisor"/>
```

## 8 [Boot and Kernel Parameters](https://angrysysadmins.tech/index.php/2022/07/grassyloki/vfio-tuning-your-windows-gaming-vm-for-optimal-performance#host-config)
```bash
#!/usr/bin/env fish
cat /proc/cmdline
kernelstub -a "vfio_iommu_type1.allow_unsafe_interrupts=1 kvm.ignore_msrs=1 intel_iommu=on iommu=pt intel_iommu=igfx_off"
```

