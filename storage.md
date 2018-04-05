# My Bare Metal Kubernetes Lab Dynamic Storage Set Up

* [Introduction](https://github.com/jfelten/My_bare_metal_k8s/blob/master/README.md#introduction)
* [Prerequisites](https://github.com/jfelten/My_bare_metal_k8s/blob/master/README.md#prereq)
* [Hardware set up](https://github.com/jfelten/My_bare_metal_k8s/blob/master/hardware.md)
* [Storage set up](https://github.com/jfelten/My_bare_metal_k8s/blob/master/storage.md)
* [Kubernetes set up](https://github.com/jfelten/My_bare_metal_k8s/blob/master/kubernetes.md)
* [Cluster operations](https://github.com/jfelten/My_bare_metal_k8s/blob/master/clusterops.md)

## Create the glusterfs storage array

Dynamic storage is not technically required, but I strongly suggest it for any kubernetes cluster.  This will let kubernetes manage the lifecycle of perisent disks used by applicaitons.  Many open source kubernetes applications assume the presence of a working default storage class, and this will allow you to run them out of the box without painful storage reconfigurations.

I chose to build my own storage array. If you do not desire this there are other options.  It is possible to allocate space directly on a node and then use a provider running inside kubernetes like [nfs](https://github.com/kubernetes-incubator/external-storage/tree/master/nfs), [rook](https://github.com/rook/rook), or even [glusterfs](https://github.com/gluster/gluster-kubernetes) to use that disk for dymanic storage.  These tie storage directly to the kubernetes nodes, but are easier to configure.

I chose to use glusterfs as my storage provide mainly because I was using an RHEL variant and I didn't have access to a proper NAS.  I did try [rook](https://github.com/rook/rook) but quickly gave up due to underlying ceph issues that looked hard to solve.  Glusterfs works out of the box on CentOS and is relatively straightforward to use.  There is even a service-based front end called heketi that can act as a dynamic storage provisioner in kubernetes.  Overall I am pleased with glusterfs.

There are many ways to run glusterfs: directly on the blades, VMS, straight up docker, or kubernetes.  There is a good [glusterfs kubernetes example](https://github.com/gluster/gluster-kubernetes) that includes heketi and a glusterfs storage class.  This example runs teh glsuter service itself inside kubernetes and mount storage direcly on the nodes.  I chose not to run gluster inside kubernetes, because I wanted a separate first-class citizen resource that is shared among multiple clusters.  I also chose not to run gluster on my blades to guard against catastrophic hardware failure.  

I designed my glusterfs peers to run inside VMs that reference virtual disks that reside on physical raid storage.  While this may seem convoluted I think it is a nice compromise that provides enough isolation while providing an independent storage solution that can be used by any kubernetes cluster. I may replace the VMs with straight up docker or lxc in the future. The only storage component that runs in kubernetes is heketi.  I have included the helm chart I use that installs a heketi server and glusterfs storage class on any kubernetes cluster in my network. 

```
             +--------------------+
             | Kubernetes cluster |
             |      +------+      |
        +-----------+heketi+----------------+
        |    |      +------+      |         |
        |    +--------------------+         |
        |                |                  |
  +-----v----+      +----v-----+      +-----v----+
  |          |      |          |      |          |
  | gluster1 |      | gluster2 |      | gluster3 |
  | peer VM  |      | peer VM  |      | peer VM  |
  |          |      |          |      |          |
  +-----+----+      +----+-----+      +-----+----+
        |                |                  |
+-------+------+  +------+-------+  +-------+------+
|              |  |              |  |              |
|Physical RAID |  |Physical RAID |  |Physical RAID |
| +----------+ |  | +----------+ |  | +----------+ |
| | Virtual  | |  | | Virtual  | |  | | Virtual  | |
| | Disk 1   | |  | | Disk 1   | |  | | Disk 1   | |
| | Disk 2   | |  | | Disk 2   | |  | | Disk 2   | |
| +----------+ |  | +----------+ |  | +----------+ |
+--------------+  +--------------+  +--------------+
```

### Steps to set up glusterfs

First, create the physical RAID disks with mdadm.  The process is well detailed on the net, and the end result is usually new a storage device /dev/md0 that represents the RAID array.  On my blades I mount /dev/md0 to /data.

```
# mdadm --create --verbose /dev/md0 --level=1 /dev/sda1 /
# mkfs.ext4 /dev/sdb1
# mkdir -p /data
# mount /dev/md0 /data

```

Now create 2 virtual 500GB disk files in the data directory of each blade:

```
# dd if=/dev/zero of=/data/k8s/kubernetes1.dsk bs=1M count=500000
# dd if=/dev/zero of=/data/k8s/kubernetes2.dsk bs=1M count=500000
```

Mount those disks as devices in a new VM used as a glusterfs peer.  In the case I take the above 2 files and attach as the devices: /dev/vdd and /dev/vde. These device will be referenced in the heketi topology file that runs on kuberentes.  Once the VM is booted create the file system with:

```
# mkfs.ext4 /dev/vdd
# mkfs.ext4 /dev/vde
```

```
<domain type='kvm' id='5'>
  <name>gluster1</name>
  <uuid>c1551355-f84a-45ae-a0b5-9d94ccc31b77</uuid>
  <memory unit='KiB'>2194304</memory>
  <currentMemory unit='KiB'>2194304</currentMemory>
  <vcpu placement='static'>2</vcpu>
  <resource>
    <partition>/machine</partition>
  </resource>
  <os>
    <type arch='x86_64' machine='pc-i440fx-rhel7.0.0'>hvm</type>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
  </features>
  <cpu mode='custom' match='exact' check='full'>
    <model fallback='forbid'>Opteron_G3</model>
    <feature policy='disable' name='monitor'/>
    <feature policy='require' name='x2apic'/>
    <feature policy='require' name='hypervisor'/>
    <feature policy='disable' name='rdtscp'/>
    <feature policy='disable' name='svm'/>
  </cpu>
  <clock offset='utc'>
    <timer name='rtc' tickpolicy='catchup'/>
    <timer name='pit' tickpolicy='delay'/>
    <timer name='hpet' present='no'/>
  </clock>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>restart</on_crash>
  <pm>
    <suspend-to-mem enabled='no'/>
    <suspend-to-disk enabled='no'/>
  </pm>
  <devices>
    <emulator>/usr/libexec/qemu-kvm</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='/data/vms/gluster1.qcow2'/>
      <backingStore/>
      <target dev='vda' bus='virtio'/>
      <alias name='virtio-disk0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x06' function='0x0'/>
    </disk>
    <disk type='file' device='disk'>
      <driver name='qemu' type='raw'/>
      <source file='/data/k8s/kubernetes1.dsk'/>
      <backingStore/>
      <target dev='vdd' bus='virtio'/>
      <alias name='k8s-disk1'/>
    </disk>
    <disk type='file' device='disk'>
      <driver name='qemu' type='raw'/>
      <source file='/data/k8s/kubernetes2.dsk'/>
      <backingStore/>
      <target dev='vde' bus='virtio'/>
      <alias name='k8s-disk2'/>
    </disk>
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <backingStore/>
      <target dev='hda' bus='ide'/>
      <readonly/>
      <alias name='ide0-0-0'/>
      <address type='drive' controller='0' bus='0' target='0' unit='0'/>
    </disk>
    <disk type='block' device='disk'>
      <driver name='qemu' type='raw' cache='none'/>
      <source dev='/dev/md0'/>
      <target dev='vdc' bus='virtio'/>
    </disk>
    <controller type='usb' index='0' model='ich9-ehci1'>
      <alias name='usb'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x05' function='0x7'/>
    </controller>
    <controller type='usb' index='0' model='ich9-uhci1'>
      <alias name='usb'/>
      <master startport='0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x05' function='0x0' multifunction='on'/>
    </controller>
    <controller type='usb' index='0' model='ich9-uhci2'>
      <alias name='usb'/>
      <master startport='2'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x05' function='0x1'/>
    </controller>
    <controller type='usb' index='0' model='ich9-uhci3'>
      <alias name='usb'/>
      <master startport='4'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x05' function='0x2'/>
    </controller>
    <controller type='pci' index='0' model='pci-root'>
      <alias name='pci.0'/>
    </controller>
    <controller type='ide' index='0'>
      <alias name='ide'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x1'/>
    </controller>
    <controller type='virtio-serial' index='0'>
      <alias name='virtio-serial0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x0'/>
    </controller>
    <interface type='bridge'>
      <mac address='00:16:3e:48:6a:64'/>
      <source bridge='br1'/>
      <target dev='vnet3'/>
      <model type='virtio'/>
      <alias name='net0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
    </interface>
    <serial type='pty'>
      <source path='/dev/pts/4'/>
      <target port='0'/>
      <alias name='serial0'/>
    </serial>
    <console type='pty' tty='/dev/pts/4'>
      <source path='/dev/pts/4'/>
      <target type='serial' port='0'/>
      <alias name='serial0'/>
    </console>
    <channel type='unix'>
      <source mode='bind' path='/var/lib/libvirt/qemu/channel/target/domain-5-gluster1/org.qemu.guest_agent.0'/>
      <target type='virtio' name='org.qemu.guest_agent.0' state='disconnected'/>
      <alias name='channel0'/>
      <address type='virtio-serial' controller='0' bus='0' port='1'/>
    </channel>
    <input type='tablet' bus='usb'>
      <alias name='input0'/>
      <address type='usb' bus='0' port='1'/>
    </input>
    <input type='mouse' bus='ps2'>
      <alias name='input1'/>
    </input>
    <input type='keyboard' bus='ps2'>
      <alias name='input2'/>
    </input>
    <memballoon model='virtio'>
      <alias name='balloon0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x07' function='0x0'/>
    </memballoon>
  </devices>
  <seclabel type='dynamic' model='dac' relabel='yes'>
    <label>+107:+107</label>
    <imagelabel>+107:+107</imagelabel>
  </seclabel>
</domain>
```

Repeat on each physical blade.  The 2 virtual disks will be used by heketi to provision dynamic storage for any kubernetes cluster.

### glusterfs configuration

With the glusterfs VMs up and running we create the storage array, and create any static volumes desired in kubernetes.  The glsuter initialization is straightforward.  I have 3 glusterfs vms (1 on each blade) with the ips: 10.10.10.17, 10.10.10.18, 10.10.10.19.  On each server run the glsuterfs peer probe for against the other 1 servers.  Ex on 10.10.10.17 run:
```
gluster peer probe 10.10.10.18
gluster peer probe 10.10.10.19
```
Once this is done the glusterfs VMs will be talking and it is now possible ot create static volumes.  In my case, I use a static volume for my OpenVPN certs and have a shared directory called /data/certs.  You can create this volume in glusterfs via:

```
sudo gluster volume create certs replica 3 10.10.10.17:/data/certs 10.10.10.19:/data/certs 10.10.10.18:/data/certs force
```

### configure heketi

Now that the gluster peers are running with attached storage let's talk about [heketi](https://github.com/heketi/heketi).  [Heketi](https://github.com/heketi/heketi) is a service written in Go that provides a RESTful interface for glusterfs operations. For this purpose let's assume a running kubernetes cluster because that's how I run heketi.  Heketi requires 2 main configurations:
A toplogy file that lists the addresses of each glsuterfs peer and a heketi.json file that references ssh keys used to execute on each peer. I have included a helm chart that I use to bootstrap heketi on my kubernetes clusters (k8s/charts/glusterfs).  To adapt this to your setup change the endpoint ips: k8s/charts/glusterfs/templates/gluster_endpoints.yaml, the ssh secrets: charts/glusterfs/templates/gluster_secret.yaml, and and custom hekei configs:   charts/glusterfs/templates/heketi_configs.yaml.  All the values are for my lab.  You will need to install your own ssh keys assuming you run VMS and add them to the hekti secrets file.

### next: [kubernetes setup](https://github.com/jfelten/My_bare_metal_k8s/blob/master/kubernetes.md)


