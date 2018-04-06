# My Bare Metal Kubernetes Lab Hardware Set Up

* [Introduction](https://github.com/jfelten/My_bare_metal_k8s/blob/master/README.md#introduction)
* [Prerequisites](https://github.com/jfelten/My_bare_metal_k8s/blob/master/README.md#prereq)
* [Hardware set up](https://github.com/jfelten/My_bare_metal_k8s/blob/master/hardware.md)
* [Storage set up](https://github.com/jfelten/My_bare_metal_k8s/blob/master/storage.md)
* [Kubernetes set up](https://github.com/jfelten/My_bare_metal_k8s/blob/master/kubernetes.md)
* [Cluster operations](https://github.com/jfelten/My_bare_metal_k8s/blob/master/clusterops.md)

## Server Chassis
The hardware is a Dell 6105c 2U rack mount server. The unit dates from 2011 or so and is set up with 3 blades each containing 48GB of DDR2 RAM and 2 6 core AMD Opteron processors for a total of 144G and 36 cores. Each blade runs CentOS 7 as the base OS. All told there is a total of $500 invested, which includes storage. The hardware is even older and cheaper now than when purchased.

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

I will provide detailed steps where important, but gloss over some things like installed CentOS.

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

Repeat on the other 2 blades and adjust the ips and subnets accordingly. These subnets are completely isolated from the lab subnet and consequently secured as long as your lab subnet has prudent security.

### Next: [Storage set up](https://github.com/jfelten/My_bare_metal_k8s/blob/master/storage.md)