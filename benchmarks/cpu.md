# CPU

| Config |  Max Threads | 1 Thread | 2 Threads | 4 Threads | 8 Threads | 16 Threads |
|--------|--------------|----------|-----------|-----------|-----------|------------|
|  1     |  4378        | 666      | 1312      | 2560      | 4731      | 4734       |
|  2     |  7280        | 660      | 1296      | 2561      | 4626      | 7656       |


## 1
```xml
  <cpu mode='host-passthrough' check='none' migratable='on'>
    <topology sockets='2' dies='1' cores='8' threads='1'/>
    <feature policy='disable' name='smep'/>
    <feature policy='disable' name='hypervisor'/>
  </cpu>
```
## 2
```xml
  <cpu mode="host-passthrough" check="none" migratable="on">
    <topology sockets="1" dies="1" cores="8" threads="2"/>
    <feature policy="disable" name="smep"/>
    <feature policy="disable" name="hypervisor"/>
  </cpu>
```
