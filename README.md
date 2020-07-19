# Simple docker vpn client with remote file shares (host/container)

This is like any other normal docker-vpn client with the exception it allows you mount a remote file share in the container, then to the host, and in any other containers pretty easily.

## Why

I found myself needing remote file shares that were **NOT** available on my host machine, but available in my containers that shared a vpn connection with my other container (that started the vpn connection).

## Requirements

- I've only tested this on linux distributions (centos), it probably won't work on windows/mac unless docker supports shared/slave bind propagation's on those operating systems.
- Docker and docker-compose installed
- Openvpn conf or ovpn files that are confirmed working

## Setup

1. Clone this repository
1. Copy .env.sample and rename .env and fill out each variable (see sample file for details on each option), see below example
```
VPN_CONFIG=/home/vpn-config
PUID=1000
PGID=1000
SUBNETS=192.168.1.1
MOUNT_COMMAND=mount -t cifs -o user="bob",password="bob" //172.41.0.9/remote /remote
MOUNT_TARGET=/remote
REMOTE_DOWNLOADS=/remote
RADARR_CONFIG=/home/radarr
```
1. Really double check the above config, cause its important your share access is correct. You may even want to start up an empty container sharing the network of a vpn container to see if you can mount the share manually first
1. Run following command
```bash
docker-compose up -d
```
1. This will bring up 3 containers in following order: openvpn-client, file-share-client, radarr
1. All the file-share-client, radarr, and your host machine wil have access to the remote file share, to verify use below commands (these are example commands based on above example settings)
```bash
ls -l /remote
docker exec file-share-client ls -l /remote
docker exec radarr ls -l /remote
```

## Explanation

I wanted to go through and explain parts of the docker-compose file to better help anyone understand whats going on

- On the surface what we are doing here is creating a vpn connection with the container "openvpn-client"
- In the docker-compose.yml I include you can see that container references an existing image, yacht7/openvpn-client, that handles most of the logic for you
- We then share this containers network with the other containers via the following line
```yaml
network_mode: service:openvpn-client
```
- The above line is very important for achieving a shared vpn connection (this applies to many different docker vpn clients out there)
- The other 2 containers both reference this network_mode.

Next lets go through each containers compose config and explain the most important bits:

```yaml
  openvpn-client:
    image: yacht7/openvpn-client
    cap_add:
      - NET_ADMIN
    ports:
      # radarr port
      - 7878:7878 
    devices:
      - /dev/net/tun
    volumes:
      - ${VPN_CONFIG}:/data/vpn
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - "SUBNETS=${SUBNETS}"
    restart: unless-stopped
```

   1. In the first line should be obvious we are reusing an existing vpn client image from docker hub called yacht7/openvpn-client
   1. (important) The next block adds capabilities to the container we need specifically cause we are going to do some special networking in this container, hence why we give the container the NET_ADMIN cap
   1. (important) The ports block exposes any ports of any containers sharing the network of this container, in this case we want to expose radarrs public port to our host
   1. (important) The devices block (passing the tun adapter) is necessary for the vpn connection to function properly
   1. The volumes block just mounts our vpn configuration to our container

```yaml
  file-share-client:
    build:
      context: .
      args:
        MOUNT_COMMAND: ${MOUNT_COMMAND}
        MOUNT_TARGET: ${MOUNT_TARGET}
    stdin_open: true
    tty: true
    cap_add:
      - SYS_ADMIN
      - DAC_READ_SEARCH
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
    depends_on:
      - openvpn-client
    network_mode: service:openvpn-client
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - ${REMOTE_DOWNLOADS}:/downloads:rw,shared
    restart: unless-stopped
```

   1. The entire build block basically lets us make a customer image from the Dockerfile included in this repository. This specific dockerfile installs nfs/cifs utils necessary for mounting nfs/cifs shares
       1. These 4 mount arguments are passed into the dockerfile and use in the entrypoint script to actually mount your remote file share
   1. stdin_open/tty are just there since I use tail -f /dev/null & to keep the file-share-client running forever (or until you stop it)
   1. (important) Like the open vpn client, this file share client needs special capabilities to be able to run "mount" commands in the container, since its disabled by default in docker
       1. SYS_ADMIN/DAC_READ_SEARCH will allow you actually execute "mount" commands successfully
   1. (important) The depends_on block is to make sure the openvpn-client is "up" before
   1. (important) The network_mode block here is service:openvpn-client, which means we are going to use the network stack of openvpn-client
   1. (important) The mounted volume section is pretty much key to allowing us to share the remote file share on the host
       1. The syntax is like this: - <HOST_PATH>:<TARGET_PATH>:rw,shared
       1. rw = read/write
       1. shared = a bind propagation that lets us bind in both directions mounts on the existing mount https://docs.docker.com/storage/bind-mounts/#configure-bind-propagation
       1. Something important here to note is the entrypoint script that this container uses does the mounting and umounting of the file share which is crucial to this working
       1. If we didn't umount on docker-compose down or docker stop <container-name> it would cause a hang on the host and you would need to umount the mounted path yourself

```yaml
  radarr:
    image: linuxserver/radarr:latest
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
    depends_on:
      - openvpn-client
      - file-share-client
    network_mode: service:openvpn-client
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - {RADARR_CONFIG}:/config
      - ${REMOTE_DOWNLOADS}:/downloads:rw,slave
    restart: unless-stopped
```

   1. (important) The depends_on block makes sure our vpn/fileshare clients are both up before we try to bring up radarr
   1. (important) The network_mode block here is service:openvpn-client, which means we are going to use the network stack of openvpn-client
   1. (important) The important bit in the volumes block like the file share client is the remote downloads mount
       1. The syntax is like this: <HOST_PATH>:<TARGET_PATH>:rw,slave
       1. rw = read/write
       1. slave = unlike the file share client this **CANNOT** be a shared mount, since its already shared in the file share client. So it must be a slave propagation type
       1. If you use shared here, radarr won't start, and you'll get a docker error

## Tips

- The vpn client I use here will prevent any hosts outside of the machine hosting the containers from accessing public ports on the machine, even if you whitelist your subnet or the ip.
- If you want to allow this, add a volume mapping (like below) to the openvpn-client
```yaml
volumes:
  - ${VPN_CONFIG}:/data/vpn
  - <PATH_TO_VPN_UP_SCRIPT>/vpn-up.sh:/etc/openvpn/up.sh
```
- This script you can get from the existing container (docker exec openvpn-client cat /etc/openvpn/up.sh), then add the below route line to the bottom of the script (replacing the variables below)
```bash
ip route add <SUBNET_IN_CIDR_NOTATION> via <DOCKER_GATEWAY_IP> dev eth0
```

## Credits

The vpn container I use in this setup is from https://github.com/yacht7/docker-openvpn-client which I kind of dissected and learned a lot from. 

I also use radarr as a secondary container to show how to share the remote file share with another container.
