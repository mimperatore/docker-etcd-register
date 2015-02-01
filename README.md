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

    # Setup up a CoreOS cluster
    $ fleetctl submit register.service
    $ fleetctl start register.service

This will start the service on all fleet-controlled nodes and immediately register all currently running containers that expose ports.  It will then start listening to Docker `start` and `die` events, updating registration information accordingly.

To see containers that have been registered:

    $ etcdctl ls --recursive /registered
    /registered/10.100.100.100
    /registered/10.100.100.100/dockerfile::elasticsearch:latest
    /registered/10.100.100.100/dockerfile::elasticsearch:latest/0f101deb0a876bd46f5aaad84e42651fb17b2d520504e7a2f0f85d3d7aee32b8

To see the details of exposed ports for a container:

    $ etcdctl get /registered/10.100.100.100/dockerfile::elasticsearch:latest/0f101deb0a876bd46f5aaad84e42651fb17b2d520504e7a2f0f85d3d7aee32b8
    [{container:0f101deb0a876bd46f5aaad84e42651fb17b2d520504e7a2f0f85d3d7aee32b8,image:dockerfile::elasticsearch:latest,ip:10.100.100.100,public_port:49165,private_port:9200,port_type:tcp}]

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
