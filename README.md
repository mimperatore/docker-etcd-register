# Docker Exposed Container Ports Registration Service

This project aims to provide a ruby-based service to detect and register exposed ports in running docker containers.
It is designed to be managed by [Fleet] as a Global service, and run in a [CoreOS] cluster.

The project is inspired by [SmartStack]'s [nerve] and Jason Wilder's [Docker Service Discovery Using Etcd and Haproxy][jwilder-etc-haproxy] blog post.

The key design goal was to have a single service running on each CoreOS node that continuously listens for Docker events
and registers/unregisters containers via CoreOs's [etcd] distributed key-value store, as they gets started and destroyed.

Unlike [nerve], this service does not currently monitor service health.  This feature may be added at a later date,
although perhaps in a separate service.

### Usage

To run it:

    $ git clone https://github.com/mimperatore/docker-etcd-register

    # Start a CoreOS cluster ensuring that the top directory of this repo is accessible
    # from the CoreOS nodes.  This can be easily done using the companion repo
    # https://github.com/mimperatore/vagrant-coreos...
    
    $ git clone https://github.com/mimperatore/vagrant-coreos
    $ cd vagrant-coreos
    
    # ...configuring the NFS portion of config/cluster.yml as follows:
    
    nfs:
      - id: share
        mapping: /path/to/docker-etcd-register:/home/core/share
        options: nolock,vers=3,udp
    
    # ... and then starting the cluster (nfsd will need to be running on your host):
    $ vagrant up
    
    # You should now be able to connect to any CoreOS node and access the docker-etcd-register
    # directory via the mounted share:
    
    $ vagrant ssh box-0 -- -A
	CoreOS beta (557.2.0)
	core@box-0 ~ $ cd share/
	core@box-0 ~/share $ ls
	Dockerfile  Gemfile  Gemfile.lock  LICENSE  README.md  register.rb  register.service
    
    core@box-0 ~/share $ fleetctl submit register.service
    core@box-0 ~/share $ fleetctl start register.service
	Triggered global unit register.service start

This will start the service on all fleet-controlled nodes and immediately register all currently running containers that expose ports.  It will then start listening to Docker `start` and `die` events, updating registration information accordingly.

It may take a couple of minutes for the container image to be pulled down from the Docker Registry and the service started.  You can observe the state of the service via:

    $ journalctl -f -u register
    core@box-0 ~/share $ journalctl -f -u register
    -- Logs begin at Wed 2015-02-18 03:20:09 UTC. --
    Feb 18 03:23:41 box-0 docker[1136]: 0e30e84e9513: Pulling fs layer
    Feb 18 03:23:43 box-0 docker[1136]: 0e30e84e9513: Download complete
    ...
    Feb 18 03:28:33 box-0 docker[1136]: 70e06297a535: Download complete
    Feb 18 03:28:33 box-0 docker[1136]: Status: Downloaded newer image for mimperatore/docker-etcd-register:latest
    Feb 18 03:28:33 box-0 systemd[1]: Started Docker Exposed Container Ports Registration Service.
    Feb 18 03:28:34 box-0 docker[1496]: Starting container registration service using ETCD_ENDPOINT=10.100.100.100:4001 for HOST_IP=10.100.100.100
    Feb 18 03:28:34 box-0 docker[1496]: Unregistering all containers on this host

To verify that it's working, you can try something like this:

	core@box-0 ~/share $ docker run -d -p 10.100.100.100::80 busybox sleep 1000
	ddd2d3a0758780a8d7ea792c79379d44ede446805c0e79034bee3ad6999e0fa7
	core@box-0 ~/share $ etcdctl ls --recursive /registered
	/registered/10.100.100.100
	/registered/10.100.100.100/busybox:latest
	/registered/10.100.100.100/busybox:latest/ddd2d3a0758780a8d7ea792c79379d44ede446805c0e79034bee3ad6999e0fa7
	core@box-0 ~/share $ etcdctl get /registered/10.100.100.100/busybox:latest/ddd2d3a0758780a8d7ea792c79379d44ede446805c0e79034bee3ad6999e0fa7
	[{"container":"ddd2d3a0758780a8d7ea792c79379d44ede446805c0e79034bee3ad6999e0fa7","image":"busybox:latest","ip":"10.100.100.100","public_port":"49153","private_port":"80","port_type":"tcp"}]


### Contributing

This project is a work in progress and not yet intended for production use.  Feedback and contributions are welcome.

### License

This project is released under the [MIT License][mit].

[SmartStack]: http://nerds.airbnb.com/smartstack-service-discovery-cloud/
[nerve]: https://github.com/airbnb/nerve
[jwilder-etc-haproxy]: http://jasonwilder.com/blog/2014/07/15/docker-service-discovery/
[Fleet]: https://coreos.com/using-coreos/clustering/
[CoreOS]: https://coreos.com/
[etcd]: https://coreos.com/using-coreos/etcd/
[mit]: http://www.opensource.org/licenses/MIT
