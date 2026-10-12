# Lab 3 validation: direct DCI from Arista spines

Test date: **2026-10-12**. Containerlab 0.80.0 / Docker / WSL2. Three cEOS 4.34.7M nodes (engineering build), two licensed Nokia IXR-X1b simulators and one IXR-D2L leaf, all SR Linux 26.7.1 build 554-g78ed635f70a. Two Linux clients provide separate L2 and L3 interfaces.

The [third lab](../labs/lab3-arista-spines) replaces the Arista site's Nokia BLs with two Arista spines. Spines route outer VXLAN packets without terminating tenant services. There is no direct spine-to-spine link. The two leaf VTEPs peer directly using multihop eBGP EVPN; every underlay node has a distinct ASN. This does not reproduce the customer's unknown EOS release, physical 7260CX3 SKU or route-reflector arrangement.

## Steady-state results

| Check | Observed result |
|---|---|
| L2, both directions, endpoint ARP flushed | 5/5 replies, 0% loss |
| L3, both directions, separate local access subnets | 5/5 replies, 0% loss |
| Inner IP MTU 1500 / DF, both services and directions | 3/3 replies, 0% loss |
| Arista leaf route to remote Nokia VTEP | Two next hops: 100.64.1.1 / Ethernet1 and 100.64.1.3 / Ethernet4 |
| Nokia leaf route to remote Arista VTEP | Two next hops: 100.64.2.0 and 100.64.2.2 |
| EVPN next-hop ownership | Remote leaf VTEPs, not spine or BL loopbacks |
| DCI captures | VXLAN on both circuits: 22 packets on DCI-1 and 23 on DCI-2 in the steady sample; service VNIs 10010 and 50000 |
| Broadcast sample | Five ARP requests sent, exactly five received at the remote client |

These captures show both circuits carrying sampled traffic. They do not qualify ASIC hashing or prove a particular traffic split under production load.

## Single-fault tests

The script first checks all six NOS control planes. Each fault remains active during the bidirectional L2/L3 and fresh-ARP probes. Fault-present VTEP FIB snapshots are retained. After restoration, the script requires all expected BGP/BFD sessions on all six NOS nodes before it proceeds.

| Fault | Result while fault remains active |
|---|---|
| Arista spine 1 paused | Bidirectional L2/L3 and fresh ARP passed |
| Arista spine 2 paused | Bidirectional L2/L3 and fresh ARP passed |
| Nokia BL 1 paused | Bidirectional L2/L3 and fresh ARP passed |
| Nokia BL 2 paused | Bidirectional L2/L3 and fresh ARP passed |
| DCI-1 disabled on Arista spine 1 | Bidirectional L2/L3 and fresh ARP passed |
| DCI-2 disabled on Arista spine 2 | Bidirectional L2/L3 and fresh ARP passed |
| Arista leaf uplink 1 disabled | Bidirectional L2/L3 and fresh ARP passed |
| Nokia leaf uplink 2 disabled | Bidirectional L2/L3 and fresh ARP passed |

All six control planes restored after every case. Final snapshots show two IPv4 BGP peers and two Up BFD sessions on each Arista node, plus one established leaf EVPN peer. Each Nokia node has three established BGP peers; the BLs have three Up BFD sessions each and the leaf has two. Both leaf FIBs again contain two remote-VTEP next hops.

[Evidence](results/lab3) includes 32 continuous ping traces, eight pairs of fault-present leaf FIB snapshots, restoration checks and the final control plane. Loss and delayed replies during fault injection are retained in [the summary](results/lab3/ping-summary.json); successful recovery probes do not imply uninterrupted service. 8 bounded traces ended without a final ping statistics block, so their transmitted/received/loss fields are left null. The published script uses SIGINT at the same 45-second watchdog limit to preserve statistics on future runs; this changes only measurement termination.

## Service isolation and complete DCI loss

The additional script changes only the Nokia leaf's import RT for one service at a time, checks that the other service remains available, and restores the RT. It then disables both direct DCI ports while both Arista spines stay running, checks that both services fail, and restores the ports.

All three checks passed: an L2 import-RT mismatch stopped L2 while L3 remained available; an L3 mismatch stopped L3 while L2 remained available; disabling both DCI ports stopped both services. Both services recovered after each restoration. See [the isolation log](results/lab3/isolation/test.log).

Lab 3 was left running after final control-plane checks. The license remains private in WSL and is excluded from this repository.

## Limits

This is functional validation of Option A over an IP DCI. cEOS is not an emulation of the physical 7260CX3 ASIC. No installed customer EOS version was provided, so this is not a maintenance-release or hardware feature qualification. The tests do not cover IPv6, production scale, hardware convergence timing, optics, leaf redundancy or host mobility. Docker pause can buffer delayed packets; raw loss and RTT observations must not be interpreted as a hardware failover SLA.
