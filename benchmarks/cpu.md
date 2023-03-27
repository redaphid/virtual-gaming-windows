# CPU

| Config |  Max Threads | 1 Thread | 2 Threads | 4 Threads | 8 Threads | 16 Threads |
|--------|--------------|----------|-----------|-----------|-----------|------------|
|  1     |  4378        | 666      | 1312      | 2560      | 4731      | 4734       |
|  2     |  7280        | 660      | 1296      | 2561      | 4626      | 7656       |
|  3     |  8051        | 663      | 1313      | 2575      | 4817      | 8051       |
|  4     |  7110        | 660      | 1301      | 2554      | 4477      | 7025       |

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
## 3 - [CPU Governor](https://mathiashueber.com/performance-tweaks-gaming-on-virtual-machines/#ib-toc-anchor-5)
```bash
#!/usr/bin/env fish
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
for file in (ls /sys/devices/system/cpu/*/cpufreq/scaling_governor)
  echo  "performance" > $file
end
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

## 4 - [topoext](https://mathiashueber.com/performance-tweaks-gaming-on-virtual-machines#ib-toc-anchor-9)
