#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  1) l2=192.168.10.11; l3=192.168.20.11; gw=192.168.20.1; remote=192.168.30.0/24; mac1=02:00:00:01:10:11; mac2=02:00:00:01:20:11 ;;
  2) l2=192.168.10.12; l3=192.168.30.12; gw=192.168.30.1; remote=192.168.20.0/24; mac1=02:00:00:02:10:12; mac2=02:00:00:02:30:12 ;;
  *) echo 'Usage: host-init.sh 1|2' >&2; exit 2 ;;
esac
ip link set eth1 address "$mac1"
ip link set eth2 address "$mac2"
ip link set eth1 mtu 1500 up
ip link set eth2 mtu 1500 up
ip addr replace "$l2/24" dev eth1
ip addr replace "$l3/24" dev eth2
ip route replace "$remote" via "$gw" dev eth2
sysctl -qw net.ipv4.ip_forward=0
