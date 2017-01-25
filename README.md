# hw-vpn

This project provides scripts and config files for 2 armbian devices
and a cheap wifi-router.  The armbian devices will automatically create
an *_unencrypted_* vpn connection and automatically tunnel everything.

The vpn connection will (usually) even work if both devices are behind
NAT.  No port forwarding rules have to be established on either side.

Typical armbian devices are raspberry pis and olimex OLinuXinos.

I have created this project to automatically tunnel netflix,...
to another country.  One of the armbian devices (the openvpn server)
was sent to a friend who allows me to use her internet connection.

Everything which connects to the wifi router is automatically tunneled
to my friend.  I can now simply switch country by connecting my
chromecast to a different wifi.


# Recreate this project

You will need a router and two armbian devices (the client and the
server).

* Log into the armbian devices and install:
  On the server:
  ```
nat-traverse
sofia-sip-bin
  ```

  On the client:
  ```
nat-traverse
isc-dhcp-server
sofia-sip-bin
  ```
  
  I prefer to first install aptitude (`sudo apt-get install aptitude`
  followed by `sudo aptitude install nat-traverse`...).

* Create a static.key `openvpn --genkey --secret static.key`
  Copy this key to both the client and server into `/etc/openvpn`
* Copy the openvpn server.conf to the `server:/etc/openvpn` and the
  client.conf to the `client:/etc/openvpn`
* Configure the network and dhcpd server on the client:
  ```
add second interface in /etc/network/interfaces see interfaces.client

# then adapt /etc/defaults/isc... and change network to eth0
# and
# /etc/dhcp/dhcpd.conf
option domain-name-servers 8.8.8.8, 8.8.4.4;

subnet 10.42.42.0 netmask 255.255.255.0 {
  range 10.42.42.100 10.42.42.200;
  option routers 10.42.42.1;
}
  ```
  Replace the content of /etc/network/interfaces on the client with
  the content of configs/interfaces.client.
  
  Enable the dhcpd server: `update-rc.d dhcpd enable`
  
  Finally restart the client.
* Copy the vpn.sh script to the server and client (`/usr/local/bin/`)
* If you don't have a github account yet, create one.
* In the github security web-interface create a new token, which only
  has `gist` access.
* Create 2 gists: a server and client gist.  The gist ids are shown
  in the urls.
* Write a config file:
  ```
# this is the configuration file for /usr/local/bin/vpn.sh

ROLE=CLIENT
MY_GIST_ID=
MY_GIST_FILE_NAME=
PEER_GIST_ID=
PEER_GIST_FILE_NAME=

TOKEN=
  ```
  `ROLE` must be either `CLIENT` or `SERVER`.  The `MY_GIST_ID` on the
  client is the same as `PEER_GIST_ID` on the server.
  
  Copy the corresponding file to `/etc/`.
* Enable `vpn.sh` by adding: `(sleep 30; /usr/local/bin/vpn.sh) &` into
  `/etc/local.rc`
* Reboot both devices and hope :)

## How does it work.

`openvpn` is used for the tunnel.

### openvpn configuration

The `openvpn` server configuration:

```
proto udp

# We don't use public/private keys, but a shared secret key.
secret static.key

# Persist key shouldn't be necessary.
# I've added it, because we change user to nobody.
# But openvpn should abort and stop if there is no connection
# (see ping settings) below.
persist-key

# NO encryption.  The static.key is only used for authentication.
cipher none

dev tun
persist-tun
# The server will have IP 10.42.8.1
# The client 10.42.8.2
ifconfig 10.42.8.1 10.42.8.2

user nobody

# If we lose the connection or no connection is established, stop.
#single-session
ping 10
ping-exit 120
ping-timer-rem

```

The openvpn client configuration is similar:
```
# remote is given through command line options
#remote remoteIP remotePORT

proto udp
secret static.key
persist-key
cipher none

redirect-gateway def1
dhcp-option DNS 8.8.8.8

dev tun
persist-tun

ifconfig 10.8.0.2 10.8.0.1


user nobody

#single-session
ping 10
ping-exit 120
ping-timer-rem

```

To generate a `static.key`: `openvpn --genkey --secret static.key`


### nat-traverse

The openvpn configuration above would require port-forwarding, if the
devices were behind NAT routers.

From the `nat-traverse` homepage:
> nat-traverse establishes connections between nodes which are behind NAT gateways

This only works for UDP connections.

Unfortunately not all NATs copy the src-port when forwarding packages.

`nat-traverse` will not work when the src-port of the udp packages is
mapped to another src-port.


### stunc

Even if the src-port is mapped, most NATs will reuse the same mapping
for all destinations.  This means that if we know to which external
port our internal port is mapped when talking to server X, we have a
good chance that the NAT router will also map our internal port to the
same external port when talking to server Y.

Using `stunc` we can ask a public stun server how a UDP package was
received.

We then tell openvpn to use the same internal src port and inform the
other openvpn about the mapped src port.


### github gist

A github gist is used to pass those informations between the devices.


## Typical flow

### Server side

1. Use `stunc` to send a UDP package to a public stun server.
2. Extract the local src port, the mapped src port and the public IP
   from the stun response.
3. Store the mapped src port and the public IP in a gist on github.
4. Fetch the corresponding github gist from the client and extract
   the mapped client src port and public client IP.
5. Try to establish a connection to the mapped client IP : mapped client src port
   with nat-traverse.
6. If successful start openvpn at the same local src port (from step 2)


### Client side

Steps 1-5 are the same (client and server reversed).

6. If successful start openvpn and pass the server public IP and port.



## `vpn.sh`

All those steps are executed in `vpn.sh` together with error handling
and retries.


# DHCP and the router

My other devices (chromecast,...) shouldn't need to know anything about
tunnels / vpn connections.  They only need to connect to the router
(either via wifi or the ethernet connection).

I have given the router and the client armbian device a static IP.

On the router DHCP is turned off.  No other device on the network knows
about the IP address of the router.

A dhcp server is installed on the client armbian device, telling all
registering devices to route traffic to the armbian client.


