# My Bare Metal Kubernetes Lab Set Up

* [Introduction](https://github.com/jfelten/README.md#introduction)
* [Prerequisites](https://github.com/jfelten/README.md#prereq)
* [Hardware set up] (https://github.com/jfelten/hardware.md)
* [Storage set up] (https://github.com/jfelten/storage.md)
* [Kubernetes set up] (https://github.com/jfelten/kubernetes.md)
* [Cluster operations] (https://github.com/jfelten/clusterops.md)

## <a name="introduction"></a>Introduction

This is a write up of my personal lab. It runs on a Dell 6105c with 3 blades. Each blade uses KVM to run virtual machines that host the kubernetes and storage nodes. It supports 3 or more clusters depending on configuration. The target cluster size is 8 physical cores 16 GB total memory, and 400 GB node storage.  Each node lives on a virtual machine that uses 2 cores, 4 GB, and 100 GB of disk. All kubernetes nodes reside on a KVM virtual machines running CentOS 7 and are managed through a set of Ansible scripts. Dynamic storage is handled through glusterfs that run independently of kubernetes. All of the required kubernetes bits to bootstrap the cluster are provided in custom helm charts that are applied after the cluster is created. I provide detailed steps, scripts, kuberentes files, and the helm charts used for my set up.

I use CentOS 7 because I am more experienced with RHEL variants. In hindsight, a Debian variant may have been a better choice due to better support for both kubernetes and KVM. CentOS does not support 9p virtio although it can be used with a custom kernel, which would have been nice for mounting host volumes. Kubernetes doesn't work out of the box on Centos without a few tweaks that are in the ansible scripts.  That being said, CentOS is stable once set up.

This set up works well for my lab needs, but I in no way advocate it for a production set-up. When it comes to bare metal there is no one size fits all, and this write is mostly useful as a point of reference. 

VMs are a nice way to divide up a large chunk of hardware for containerization, but I am seriously considering lxc as well.

## <a name="prereq"></a>Prerequisites

You'll need hardware and lots of it.  A kubernetes cluster requires three things: CPU, memory, and disk.  Each node should at a minimum have at least one CPU core,  twoGB of RAM, and enough disk to store several large docker files.  

Extra storage for dynamic allocation by kubernetes is also recommended because many kubernetes examples and helm charts assume a working default storage provider for persistent volumes.  If you are fortunate enough to have extra dedicated SAN avaiable use it.  Otherwise you'll have to cobble together one like I did with glusterfs.

How a bare metal cluster is built depends the underlying hardware.  Once there are 3 or more servers/VMs with enough resources are running the kubernetes install works the same regardless.  The ansible scripts provided here would work just as well for a kubernetes cluster running on a cloud provider.

In order to use the ansible and kubernetes scripts you'll need a place to run them be it a developer laptop or VPC in the cloud.  This environment should at a minimum have git, ansible, kubectl and helm installed.  A text editor too, which should go without saying.

### next: [hardware setup](https://github.com/jfelten/hardware.md)
