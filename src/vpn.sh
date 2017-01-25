#!/bin/bash

# This net must be the net on the client side.
# (See dhcp-server)
NATTED_NET="10.42.42.0 255.255.255.0"

set -x

# source the configuration
source /etc/vpn.conf

# The following variables should now be set:
#ROLE
#MY_GIST_ID
#MY_GIST_FILE_NAME
#PEER_GIST_ID
#PEER_GIST_FILE_NAME
#
#TOKEN

sysctl -w net.ipv4.ip_forward=1
if [ "$ROLE" = "SERVER" ]
then
  iptables -t nat -A POSTROUTING -s 10.42.0.0/16 -o eth0 -j MASQUERADE
fi

while true
do
  # We use stun to find a port mapping.
  # stunc will use a random local port as source and ask the stun server
  # what IP and port will arrive as source at the server.
  STUN_RESP=$(stunc stun.l.google.com:19302 -b 2>&1)

  # Even though some NATs don't keep ports, mappings usually are reused.
  # If for instance 192.168.1.2:1234 (1234 being the local source port)
  # is seen as coming from 8.8.8.8:4321 at server stun.l.google.com
  # apparently nearly all NAT routers will keep the 1234 → 4321 mapping
  # for other destinations.
  # 192.168.1.2:1234 would also be seen as 8.8.8.8:4321 at server
  # stun1.amazon.com. 

  # stunc unfortunately doesn't allow us the specify a source port.
  # Instead we will extract the randomly choosen source port and
  # start the openvpn at that port.  (Easier than finding and installing
  # another program.)

  # LOC_PORT will contain the selected local source port
  LOC_PORT=$(printf "%s" "$STUN_RESP" | grep 'local socket is bound to' | sed 's/.*://')
  # PUB_DATA will contain the visible IP and port (ex: 8.8.8.8:1234)
  PUB_DATA=$(printf "%s" "$STUN_RESP" | grep 'local address NATed' | sed 's/.* //')

  if [ "X$LOC_PORT" = "X" ] || [ "X$PUB_DATA" = "X" ] 
  then
    sleep 10
    continue
  fi

  # We use github gist to inform our peer how to reach us:
  curl -s --request PATCH \
    -H "Authorization: token $TOKEN" \
    -d "{\"files\": {\"$MY_GIST_FILE_NAME\": {\"content\": \"$PUB_DATA\"}}}" \
    https://api.github.com/gists/$MY_GIST_ID > /dev/null

  declare -i TRIES=0
  while [ $TRIES -lt 10 ]
  do
    PEER_DATA=$(curl -s \
      -H "Authorization: token $TOKEN" \
      https://api.github.com/gists/$PEER_GIST_ID \
      | python3 -c "import sys, json; print(json.load(sys.stdin)['files']['$PEER_GIST_FILE_NAME']['content'])")

    PEER_IP="${PEER_DATA/:*/}"
    PEER_PORT="${PEER_DATA/*:/}"

    if [ "X$PEER_IP" = "X" ] || [ "X$PEER_PORT" = "X" ]
    then
      TRIES=$TRIES+1
      sleep 30
      continue
    fi

  
    declare -i TRIES_TRAVERSE=0
    while [ $TRIES_TRAVERSE -lt 6 ]
    do
      if nat-traverse --quit-after-connect $LOC_PORT:$PEER_DATA
      then
        if [ "$ROLE" = "SERVER" ]
        then
          openvpn --status /run/openvpn/server.status 10 \
                  --cd /etc/openvpn \
                  --script-security 2 \
                  --config /etc/openvpn/server.conf \
                  --writepid /run/openvpn/server.pid \
                  --port $LOC_PORT \
		  --route $NATTED_NET
        else
          openvpn --status /run/openvpn/server.status 10 \
                  --cd /etc/openvpn \
                  --script-security 2 \
                  --config /etc/openvpn/client.conf \
                  --writepid /run/openvpn/server.pid \
                  --remote $PEER_IP \
                  --port $PEER_PORT \
                  --lport $LOC_PORT
        fi
	TRIES_TRAVERSE=0
      else
        sleep 5
	TRIES_TRAVERSE=$TRIES_TRAVERSE+1
      fi
    done
    sleep 5
    TRIES=$TRIES+1
  done
done

