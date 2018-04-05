# My Bare Metal Kubernetes Lab Set Up

This is a write up of my personal lab. It runs on a Dell 6105c with 3 blades. Each blade uses KVM to run virtual machines that host the kubernetes and storage nodes. It supports 3 or more clusters depending on configuration. The target cluster size is 8 physical cores 16 GB total memory, and 400 GB node storage.  Each node lives on a virtual machine that uses 2 cores, 4 GB, and 100 GB of disk. All kubernetes nodes reside on a KVM virtual machines running CentOS 7 and are managed through a set of Ansible scripts. Dynamic storage is handled through glusterfs that run independently of kubernetes. All of the required kubernetes bits to bootstrap the cluster are provided in custom helm charts that are applied after the cluster is created. I provide detailed steps, scripts, kuberentes files, and the helm charts used for my set up.

I use CentOS 7 because I am more experienced with RHEL variants. In hindsight, a Debian variant may have been a better choice due to better support for both kubernetes and KVM. CentOS does not support 9p virtio although it can be used with a custom kernel, which would have been nice for mounting host volumes. Kubernetes doesn't work out of the box on Centos without a few tweaks that are in the ansible scripts.  That being said, CentOS is stable once set up.


## Server Chassis
The hardware is a Dell 6105c 2U purchased a few years ago.  The hardware dates from 2011 or so and is set up with 3 blades each containing 48GB of DDR2 RAM and 2 6 core AMD Opteron processors for a total of 144G and 36 cores. Each blade runs CentOS 7 as the base OS.  All told I have about $500 invested.  The hardware is even older and cheaper now than when I purchased it.

## Storage
Each blade accesses 4 physical drives of varying amounts of storage for a total of 12 physical SATA drives. On two of the blades, I set up RAID 1 storage consisting of two drives. One blade has a RAID 0 storage. The disk arrays are used to back a glusterfs storage array that is then used by all kubernetes clusters.

#### Disk arrangement as viewed from the front of the chassis:

```
                           +-----------------+
                           |    RAID 1       |
       +-------+ +-------+ +-------+ +-------+
Blade 1| 500 GB| | 500 GB| | 2  TB | | 2  TB |
       +-------+ +-------+ +-------+ +-------+
                                RAID 0
       +-------+ +-------+ +-------+ +-------+
Blade 2| 500 GB| | 250 GB| | 2  TB | | 1.5 TB|
       +-------+ +-------+ +-------+ +-------+
                                RAID 1
       +-------+ +-------+ +-------+ +-------+
Blade 3| 250 GB| | 250 GB| | 750 GB| | 750 GB|
       +-------+ +-------+ +-------+ +-------+
```

## Host Network

Each blade has 2 physical NICs. Each NIC uses bridged networking. NIC 1 on each blade is joined to Linux bridge designated br0, which uses the main lab network 10.10.10.0/24. NIC 2 on each host uses a bridge-
designated br1, and each blade has a different subnet (blade1: 10.10.1.0/24, blade 2: 10.10.2.0/24, blade 3 10.10.3.0/24.) The second NIC network is used for all node VMs; the intent is to isolate kubernetes clusters on a separate network.

```
            NIC 1: Lab Network  NIC 2: k8s Network
+---------- +----------------+  +----------------+
| Blade 1 | | 10.10.10.0/24  |  | 10.10.1.0/24   |
|         | +----------------+  +----------------+
|         |
|         | +----------------+  +----------------+
| Blade 2 | | 10.10.10.0/24  |  | 10.10.2.0/24   |
|         | +----------------+  +----------------+
|         |
|         | +----------------+  +----------------+
| Blade 3 | | 10.10.10.0/24  |  | 10.10.3.0/24   |
+---------- +----------------+  +----------------+
```

## Base OS installation

I will provide detailed steps where important

Install CentOS 7 minimal and then add packages as needed. I prefer to keep the blade OS install as clean and minimal as possible, but you will need the libvirtd packages to run KVM.  Any service not related to keeping the node alive should be run in a VM or container.

### Network setup

Each blade has 2 physical NICs and each NIC gets enslaved to a different bridge.  Interface 1, en0 is enslaved to bridge br0, which is given a static IP on network 10.10.10.0/24, the lab network. Interface 2, en1, is enslaved to bridged br1 which is a separate subnet shared by kubernetes node VMs.

First create the bridge br1, which will be the general lab network. There are tools to do this, but I find it easier to just add the file: /etc/sysconfig/network-scripts/ifcfg-br1.

```
cat /etc/sysconfig/network-scripts/ifcfg-br1
DEVICE=br1
TYPE=Bridge
BOOTPROTO=none
ONBOOT=yes
IPADDR=10.10.10.13
DNS1=8.8.8.8
NETMASK=255.255.255.0
GATEWAY=10.10.10.1
```

The physical NICs are designated as p4p1 and p4p2.  Each one will be enslaved to a bridge.  In this case, en1 is enslaved to bridge br1 by changing the interface file:

```
cat /etc/sysconfig/network-scripts/ifcfg-p4p2
DEVICE=p4p2
ONBOOT=yes
BOOTPROTO=none
BRIDGE=br1
```

Next, create the bridge br0 and enslave it to the interface p4p1.  Since we are on blade 3 we will have the bridge address will be 10.10.3.1 and act as a gateway for any VMs created:

```
cat /etc/sysconfig/network-scripts/ifcfg-br0
DEVICE=br0
TYPE=Bridge
BOOTPROTO=none
ONBOOT=yes
IPADDR=10.10.3.1
DNS1=8.8.8.8
NETMASK=255.255.255.0

cat /etc/sysconfig/network-scripts/ifcfg-p4p1
DEVICE=p4p1
ONBOOT=yes
BOOTPROTO=none
BRIDGE=br0
```

Repeat on the other 2 blade adjust the ips and subnets as needed.

### create a kvm node template

My approach to VMs is to create once then clone.  My naming schema for nodes is cluster<CLUSTER_NUM>n<NODE_NUM>/ Create a kvm VM called cluster1n1( cluster 1 node 1) attached to bridge br1 and install CentOS 7 minimal via:

```bash
# virt-install \
--virt-type=kvm \
--name cluster1n1 \
--ram 4096 \
--vcpus=2 \
--os-variant=centos7.0 \
--cdrom=/var/lib/libvirt/boot/CentOS-7-x86_64-Minimal-1708.iso \
--network=bridge=br1,model=virtio \
--graphics vnc \
--disk path=/var/lib/libvirt/images/centos7.qcow2,size=100,bus=virtio,format=qcow2
```

Once a vm is created get the xml definition:

```bash
# virsh dumpxml cluster1n1 > cluster1n1.xml
```

Now copy the cluster1n1.xml file 3 times to create the cluster1n2-cluster1n4 XML files.  Copy the disk files as well and rename the references in the resulting XML files.  Also be sure to edit the files to give each VM and to give each clone a unique network MAC address.  Here is a python script that generates a random MAC address:

```bash
cat generateMac.sh
#!/usr/bin/env python
 
import random

def randomMAC():
    return [ 0x00, 0x16, 0x3e,
        random.randint(0x00, 0x7f),
        random.randint(0x00, 0xff),
        random.randint(0x00, 0xff) ]

def MACprettyprint(mac):
    return ':'.join(map(lambda x: "%02x" % x, mac))

if __name__ == '__main__':
    print(MACprettyprint(randomMAC()))
```

Here is an example xml definition file:

```
<domain type='kvm' id='5'>
  <name>cluster3n1</name>
  <memory unit='KiB'>4194304</memory>
  <currentMemory unit='KiB'>4194304</currentMemory>
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
      <driver name='qemu' type='qcow2' cache='none' io='native'/>
      <source file='/data/vms/cluster3n1.qcow2'/>
      <backingStore/>
      <target dev='vda' bus='virtio'/>
      <alias name='virtio-disk0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x06' function='0x0'/>
    </disk>
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <backingStore/>
      <target dev='hda' bus='ide'/>
      <readonly/>
      <alias name='ide0-0-0'/>
      <address type='drive' controller='0' bus='0' target='0' unit='0'/>
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
      <mac address='00:16:3e:6b:c4:72'/>
      <source bridge='br0'/>
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
      <source mode='bind' path='/var/lib/libvirt/qemu/channel/target/domain-5-cluster3n1/org.qemu.guest_agent.0'/>
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

Much of this could be automated, but I have not had to do it enough to justify the effort.

## Create the glusterfs storage array

I chose to use glusterfs as my storage provide mainly because I was using an RHEL variant.  I did try rook but quickly gave up due to underlying ceph issues that looked hard to solve.  Glusterfs works out of the box on CentOS and is relatively straightforward to use.  There is even a service-based front end called heketi that can act as a dynamic storage provisioner in kubernetes.  Overall I am pleased with glusterfs.

There are many ways to run glusterfs: directly on the blades, VMS, straight up docker, or kubernetes.  There is a nice example glusterfs kubernetes example that includes heketi and a glsuterfs storage class.  I chose not to run gluster inside kubernetes, because I wanted it to be a separate first-class citizen resource that is shared among multiple clusters.  I also chose not to run gluster on my blades to avoid catastrophic hardware failure.  

I chose to run my gluster peers inside VMs that reference virtual disks that reside on physical raid storage.  While this may seem convoluted I think it is a nice compromise that provides enough isolation that provides a single storage set that can be used by any kubernetes cluster. I may replace the VMs with straight up docker. containers running directly on the node.  The only storage piece that runs in kubernetes is heketi.  I have included the helm chart I use that installs a heketi server and glusterfs storage class on any kubernetes cluster in my network. 

Here are the steps used to set up gluster:

First, create the physical RAID disks with mdadm.  The process is well detailed on the net, and the end result is usually new a storage device /dev/md0 that represents the RAID array.  I use this to store all of my VM disks and other large files.

Now create 2 virtual 500GB disk files:

```
dd if=/dev/zero of=kubernetes1.dsk bs=1M count=500000
dd if=/dev/zero of=kubernetes2.dsk bs=1M count=500000
```

Mount those disks as devices in a new VM used for a gluster server.

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

### glusterfs set up

With the glusterfs VMs up and running we now need to make them talk with each other, and create any static volumes desired in kubernetes.  The glsuter initialization is straightforward.  I have 3 glusterfs vms (1 on each blade) with the ips: 10.10.10.17, 10.10.10.18, 10.10.10.19.  On each server run the glsuterfs peer probe for against the other 1 servers.  Ex on 10.10.10.17 run:
```
gluster peer probe 10.10.10.18
gluster peer probe 10.10.10.19
```
Once this is done the glusterfs VMs will be talking and it is now possible ot create static volumes.  In my case, I use a static volume for my OpenVPN certs and have a shared directory called /data/certs.  You can create this volume in glusterfs via:
```
sudo gluster volume create certs replica 3 10.10.10.17:/data/certs 10.10.10.19:/data/certs 10.10.10.18:/data/certs force
```

## Kubernetes Finally

Now that the physical hardware, storage, and VM nodes are set up it is time install kubernetes.  For this, I have created ansible scripts to manage the life cycle of the kubernetes clusters.

| Script              | Purpose                                             |
|---------------------|:---------------------------------------------------:|
|install_k8s.yaml     | Installs the kubernetes software on each node       |
|create_cluster.yaml  | creates a new cluster using kubeadm                 |
|upgrade.yaml         | upgrades a cluster to the new version using kubeadm |

First create an ansiable inventory file for the cluster:

```
cat cluster1
[nodes]
cluster1n1 ansible_ssh_host=10.10.1.11 ansible_ssh_user=<MY_USER> ansible_ssh_private_key_file=~/.ssh/id_rsa ansible_become_pass=<MY_PASSWORD>
cluster1n2 ansible_ssh_host=10.10.1.12 ansible_ssh_user=<MY_USER> ansible_ssh_private_key_file=~/.ssh/id_rsa ansible_become_pass=<MY_PASSWORD>
cluster1n3 ansible_ssh_host=10.10.1.13 ansible_ssh_user=<MY_USER> ansible_ssh_private_key_file=~/.ssh/id_rsa ansible_become_pass=<MY_PASSWORD>
cluster1n4 ansible_ssh_host=10.10.1.14 ansible_ssh_user=<MY_USER> ansible_ssh_private_key_file=~/.ssh/id_rsa ansible_become_pass=<MY_PASSWORD>

[nodes:vars]
master_ip=10.10.1.11
docker_version=17.03.2
external_ip=<MY_EXTERNAL_IP>
api_port=6443
kubeadm_network_addon_url=https://cloud.weave.works/k8s/net?k8s-version=
cluster_name="cluster 1"

```
The first node is always considered the master by the ansible scripts:

| variable                | Purpose                                                      |
|-------------------------|:-----------------------------------------------------------:|
|external_ip              | an externally available address - in my case ISP assigned IP|
|docker_version           | version of docker installed on nodes                        |
|api_port=6443            | cluster API port                                            |
|kubeadm_network_addon_url| URL use to install cluster network add-on                   |
|cluster_name             | Name of this cluster                                        |

To install kubernetes:

```
ansible-playbook ansible/install_k8s.yaml -i ansible/cluster1
```

To create the cluster:

```
ansible-playbook ansible/create_cluster.yaml -i ansible/cluster1
```

To upgrade an existing clsuter to the latest version of kubernetes:
 
```
ansible-playbook ansible/upgrade.yaml -i ansible/cluster1
```
