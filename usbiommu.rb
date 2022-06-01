lsusb = `lsusb`.split("\n").reject { |x| x.include?("root") }.map do |e|
  ar = e.scan(/Bus (\d+) Device \d+: ID [0-9a-f:]+ (.*)/).flatten
  ar[0] = "usb#{ar[0].to_i}"
  ar
end

sysbus = `ls -l /sys/bus/usb/devices`.split("\n").map do |e|
  e.scan(/(usb\d+) -> .+\/([0-9a-f:\.]+)\/usb\d+/).flatten
end.reject { |x| x.empty? }

iommu = Dir.glob("/sys/kernel/iommu_groups/*/devices/*").map do |e|
  arr = e.scan(/iommu_groups\/(\d+)\/devices\/([0-9a-f:\.]+)/).flatten
  arr[0] = arr[0].to_i
  pci = `lspci -nns #{arr[1]}`.strip.scan(/\[([0-9a-f:]+)\]/).flatten.last
  [arr, pci].flatten
end

mapped = {}

lsusb.map do |usb, name|
  mapped[usb] ||= { devices: [] }
  pci = sysbus.find { |x| x.first == usb }[1]
  mmu = iommu.find { |x| x[1] == pci }

  mapped[usb][:devices] << name
  mapped[usb][:pci] = pci
  mapped[usb][:pcidetail] = mmu.last
  mapped[usb][:iommu] = mmu.first
  mapped[usb][:iommu_count] = iommu.find_all { |x| x.first == mmu.first }.count
end

mapped.sort.each do |k, v|
  puts k
  puts " - PCI: #{v[:pci]} [#{v[:pcidetail]}]"
  puts " - IOMMU: Group #{v[:iommu]} (#{v[:iommu_count]} device(s) on group)"
  puts " - Devices:"
  puts v[:devices].map { |x| "  - #{x}" }.join("\n")
end