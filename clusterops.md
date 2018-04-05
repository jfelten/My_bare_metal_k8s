# My Bare Metal Kubernetes Lab Cluster Operations

* [Introduction](https://github.com/jfelten/README.md#introduction)
* [Prerequisites](https://github.com/jfelten/README.md#prereq)
* [Hardware set up](https://github.com/jfelten/hardware.md)
* [Storage set up](https://github.com/jfelten/storage.md)
* [Kubernetes set up](https://github.com/jfelten/kubernetes.md)
* [Cluster operations](https://github.com/jfelten/clusterops.md)

## Cluster Operations

Once kubernetes is running I have not seen it fail catestrpohically.  Most of the issues I have experienced are related to the underlying hardware and environment.

That is not to say dealing with kubernetes is easy. Each new kubernetes version brings new failures, undocumented requirements, or exposes weakness that previously were not an issue. Kubernetes is a complex beast so a lot of these issues are understandable.

I am constantly having to tweak the ansible scripts to keep up, but the tweaks have been getting easier recently. 
 
Being primarily a dev environment my cluster operations are pretty simple:

* If something breaks I fix it.
* Every 2 weeks or so I upgrade my clusters to the latest and greatest that kubeadm supports and tweak the scripts as necessary.

I always try to run the newest version possible unless I know a release is problematic.  In that case I just wait for the next release.  As of this writing I am running kubernetes version 1.10.0.

### problems encountered

* Power failures - My server sits in an anonymous garage in an area prone to winter storms.  I do not have the luxury of a clean data center with surge supression/backup generator so I experience a lot of abrupt shutdowns.  I have had to spend a lot of time massaging the server to make sure all VMs and services restart properly when the power comes back.  It took a lot of time and deligence to make sure the server recovers fro ma hard shutdown, but it is stable for now.
* VM failure - during once such hard shut down one of the gluster VM's oeprating system disk became corrupted and had to be rebuit. Always keep backups!
* Kubernetes upgrade hell - The kubeadm uopgrade from 1.7 to 1.8 was particuarly troublesome and required a complete rebuild of all clusters.

Right now all is well and as kubernetes matures I am hoping it becomes more stable.  IF you have a bare metal cluster and want to standardize on a toolset or need to test something on bare metal let me knw.