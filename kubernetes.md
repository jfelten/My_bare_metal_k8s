# My Bare Metal Kubernetes Lab Cluster Installation

* [Introduction](https://github.com/jfelten/README.md#introduction)
* [Prerequisites](https://github.com/jfelten/README.md#prereq)
* [Hardware set up] (https://github.com/jfelten/hardware.md)
* [Storage set up] (https://github.com/jfelten/storage.md)
* [Kubernetes set up] (https://github.com/jfelten/kubernetes.md)
* [Cluster operations] (https://github.com/jfelten/clusterops.md)

## Create a Kubernetes cluster that runs in kvm based nodes

I use VMs to divide up my hardware.  While it is tempting to install a large cluster running directly on each blade I decided to use vm templates for the flexibility, safety and isolation. There are breakages and incompatibilities with each new kubernetes release and I usually have to massage the node image and ansible scripts.

For reliability I try to keep my blade OS as simple and unencumbered as possible.

### cluster node sizing

At this point in time sizing a kubernetes node is more art than science and depends a lot on what it runs.  I have standardized on 4 node clusters with 4 GB RAM 2 CPU cores, and 100 GB of disk.  This should be enough to run most medium sized applications.  As time passes node resources will be adjusted as necessary.

### create a kvm node template

My approach to VMs is to create once then clone.  The naming schema for nodes is cluster\<CLUSTER#>n\<NODE#>.  

To starc reate a kvm VM called cluster1n1( cluster 1 node 1) attached to bridge br1 and install CentOS 7 minimal via:

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


## Install Kubernetes On Each Node In the Cluster

Now that the physical hardware, storage, and VM nodes are set up it is time install kubernetes.  For this, I have created ansible scripts to manage the life cycle of the kubernetes clusters.

All my clusters are simple 1 master/etcd non high avialbabiltiy (HA) clsuters created via kubeadm.  Once running they work great for lab purposes. They could be adapted for productions use by using multiple clsuters through a load blancer, but I have had no reason to do that yet.

| Script              | Purpose                                             |
|---------------------|:---------------------------------------------------:|
|install_k8s.yaml     | Installs the kubernetes software on each node       |
|create_cluster.yaml  | creates a new cluster using kubeadm                 |
|upgrade.yaml         | upgrades a cluster to the new version using kubeadm |

First create an ansible inventory file neamed clsuter for the first cluster:

```
cat cluster1
[nodes]
cluster1n1 ansible_ssh_host=10.10.1.11 ansible_ssh_user=<MY_USER> ansible_ssh_private_key_file=~/.ssh/id_rsa ansible_become_pass=<MY_PASSWORD>
cluster1n2 ansible_ssh_host=10.10.1.12 ansible_ssh_user=<MY_USER> ansible_ssh_private_key_file=~/.ssh/id_rsa ansible_become_pass=<MY_PASSWORD>
cluster1n3 ansible_ssh_host=10.10.1.13 ansible_ssh_user=<MY_USER> ansible_ssh_private_key_file=~/.ssh/id_rsa ansible_become_pass=<MY_PASSWORD>
cluster1n4 ansible_ssh_host=10.10.1.14 ansible_ssh_user=<MY_USER> ansible_ssh_private_key_file=~/.ssh/id_rsa ansible_become_pass=<MY_PASSWORD>

[nodes:vars]
docker_version=17.03.2
external_ip=<MY_EXTERNAL_IP>
api_port=6443
kubeadm_network_addon_url=https://cloud.weave.works/k8s/net?k8s-version=
cluster_name="cluster 1"

```
Important to note: <B>The first node, which in htis case is cluster1n1, is always considered the master by these ansible scripts.  This is particularly important when creating and upgrading the cluster.</b>

| variable                | Purpose                                                      |
|-------------------------|:-----------------------------------------------------------|
|external_ip              | an externally available address - in my case ISP assigned IP|
|docker_version           | version of docker installed on nodes                        |
|api_port=6443            | cluster API port                                            |
|kubeadm_network_addon_url| URL use to install cluster network add-on                   |
|cluster_name             | Name of this cluster                                        |

To install kubernetes on all nodes in the inventory file clone this repo and run:

```
ansible-playbook ansible/install_k8s.yaml -i ansible/cluster1
```

The ansible script installs docker, kubernetes and kubeadm via the offical kubernetes yum repo.  <b>Kubernetes does not run on CentOS out of the box.  Considerable massaging of the OS is needed.</b> All of th<is is encasulated by the ansible install script. For example it turns off swap memory and sets the right cgroups for the kubelet service. Review the ansible install script for details.


## Create the Cluster:

All clsuters get created via kubeadm. Kubeadm is a tool that automates cluster creation, and it is further automated by using ansible to coordinate on all the nodes in the cluster.

The create cluster script can be run again to regenerate kube api key.  currently I only genreate one key since it is only me and a few others that use the clsuter.

To create the cluster run the ansible script:

```
ansible-playbook ansible/create_cluster.yaml -i ansible/cluster1
```

## Upgrading to a newer version of kubernetes

The thrid ansible script upgrades and existing clsuter to a new version of kubernetes. Since I live on the bleeding edge I just always to the latest. Kubeadm does support specific kubernetes version installs so the script could be adpated to install a specific kubernetes version

To upgrade an existing cluster to the latest version of kubernetes:
 
```
ansible-playbook ansible/upgrade.yaml -i ansible/cluster1
```

### next: [cluster operations](https://github.com/jfelten/clusterops.md)
