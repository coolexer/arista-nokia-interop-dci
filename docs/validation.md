# Validation report

## Original six-node baseline

The tables below describe the initial one-BL-per-site labs at commit `c981570`. The current topologies have two BLs per site; their separate HA evidence is described later. The historical DCI-outage result applies to the original single circuit, not to a single circuit in the redundant topology.

Test date: 2026-10-09. Environment: Containerlab 0.79.0, Docker in WSL2; SR Linux 26.7.1 build 554-g78ed635f70a; cEOS 4.34.7M-48746980.4347M (engineering build).

## Option A — tested

| Check | Observed result |
|---|---|
| Border-leaf platform | Both report 7250 IXR-X1B |
| L2, both directions | 5/5 ICMP replies, 0% loss after ARP cache flush |
| L3, both directions | 5/5 replies, 0% loss; routed replies have TTL 62 |
| Inner IP MTU 1500 / DF | 3/3 replies in each direction for both services |
| DCI encapsulation | VXLAN VNI 10010 and 50000; outer addresses are leaf VTEPs |
| Remote L3 prefix | 192.168.20.0/24 on Nokia; 192.168.30.0/24 on Arista |
| RT-5 interoperability | Arista route received on SR Linux with VNI 50000, gateway IP 0.0.0.0 and router-MAC community |
| L2 import-RT mismatch | L2 failed; L3 continued; L2 restored after original RT returned |
| L3 import-RT mismatch | L3 failed with network unreachable; L2 continued |
| DCI port down | Both services failed |
| Final recovery check | After BGP convergence, both services returned 5/5 replies, 0% loss |

The initial recovery probe at 10 seconds was too early for DCI BGP reconnection; a later manual check confirmed recovery. The negative-test log records the early probe, and the table records the final check. No convergence-time SLA was measured. A was shut down after validation.

Selected [raw CLI/capture evidence](results/option-a) has neutralized lab names. The original configuration topology was the same; public files use local image tags instead of registry-qualified names. No software distributions or license keys are included.

## Option B — tested; left running

| Check | Observed result |
|---|---|
| L2, both directions | 5/5 replies, 0% loss after ARP cache flush |
| L3, both directions | 5/5 replies, 0% loss; routed replies have TTL 60 |
| Inner IP MTU 1500 / DF | 3/3 replies in each direction for both services |
| Local fabric encapsulation | VXLAN VNI 10010 and 50000 in both fabric captures |
| DCI encapsulation | MPLS ethertype 0x8847; observed SR transport and service/BUM labels; no E2E VXLAN |
| IS-IS / SR transport | One DCI adjacency; SR-ISIS tunnels between gateway loopbacks |
| L3 re-origination | Remote 192.168.20.0/24 received at DC2 gateway from 10.255.1.254 with MPLS RT 65000:60000 and D-PATH domain 65000:1 |
| L2 MPLS import-RT mismatch | L2 failed; L3 continued; L2 restored |
| L3 MPLS import-RT mismatch | L3 failed; L2 continued; L3 restored |
| DCI port down / restore | Both failed; both restored, final 3/3 replies with 0% loss |

See [selected CLI/capture evidence](results/option-b) and the negative-test log. Both configurations were accepted at startup. The gateway stitching paths were exercised by traffic across the two sites, with separate local VXLAN and DCI MPLS captures.

## Two-BL-per-site validation

The current topologies have eight nodes, including four licensed X1b simulators. They use two DCI circuits and local BL interlinks. See [the design and mechanisms](redundancy.md).

### Option A — completed

| Check | Result |
|---|---|
| Steady L2/L3, both directions | 5/5 replies, 0% loss |
| DF inner IP MTU 1500 | 3/3 replies in each direction for both services |
| ECMP FIB | Arista has next hops 100.64.1.1 / 100.64.1.3; Nokia has 100.64.2.0 / 100.64.2.2 toward the remote VTEP |
| Gateway BFD | All three sessions Up on each of the four BLs after restoration; active interval 1 s |
| Gateway BGP | All three peers Up on each BL after the tests |
| Each of four BLs paused individually | Both services recovered with the fault still present; fresh endpoint ARP also passed |
| Each DCI circuit disabled individually | Both services recovered with the fault still present |
| Selected DC1/DC2 leaf uplinks disabled | Both services recovered with the fault still present |
| Broadcast sample | Five broadcast ARP requests sent; exactly five received at the remote client |
| Final restoration | All gateway BFD/BGP sessions and both Arista ECMP paths restored |

[A HA evidence](results/option-a-ha) includes 32 continuous ping traces, steady-state captures, final control-plane state and the broadcast sample. Pausing a gateway can buffer packets: a final 0% loss statistic does not mean uninterrupted forwarding. Some delayed replies arrived after unpause with RTTs of many seconds. In the DCI-2 case the short continuous traces ended before eventual recovery, reporting about 90% loss; the later steady probes with the port still disabled passed. This run waited for service recovery between cases. The published script was subsequently strengthened to wait for full BFD/BGP restoration before the first fault and after every case, as used for the B run.

The A capture sample used DCI-1 despite two installed FIB next hops; it does not demonstrate an even load split. The other circuit and local interlinks were exercised by the outage checks. No convergence-time or load-balancing performance claim is inferred from this simulator run.

### Option B — completed; left running

Bidirectional L2/L3 and DF MTU 1500 passed with no steady-state loss. Both leaf IP-VRFs installed two local gateway next hops (.253 and .254). Local fabric captures show VXLAN VNIs 10010 / 50000; DCI captures show MPLS and no end-to-end VXLAN. TI-LFA and its required LFA parent are enabled. The broadcast sample delivered each of five requests once. All four gateways reached six established BGP peers and three Up BFD sessions before the final fault run; BGP and IS-IS share the local-interlink BFD session.

| Fault | Result with fault still present |
|---|---|
| DC1 BL paused | Bidirectional L2/L3 and fresh ARP passed |
| DC1 BL2 paused | Bidirectional L2/L3 and fresh ARP passed |
| DC2 BL paused | Bidirectional L2/L3 and fresh ARP passed |
| DC2 BL2 paused | Bidirectional L2/L3 and fresh ARP passed |
| DCI-1 port disabled | Bidirectional L2/L3 and fresh ARP passed |
| DCI-2 port disabled | Bidirectional L2/L3 and fresh ARP passed |
| DC1 BL leaf-facing uplink disabled | Bidirectional L2/L3 and fresh ARP passed; local BL IPv4 iBGP provides the fabric bypass |
| DC2 BL2 leaf-facing uplink disabled | Bidirectional L2/L3 and fresh ARP passed |

Before the first fault and after every restoration, the script verified all three BFD sessions and all six BGP peers on the relevant gateways. Final snapshots confirm all four gateways restored and both leaf IP-VRFs again using two gateway next hops. The MPLS state confirms installed SR-IS-IS tunnels. The snapshots do not separately qualify TI-LFA repair programming or hardware repair time. [B HA evidence](results/option-b-ha) includes the full fault log, 32 continuous ping traces, control-plane snapshots and captures. Gaps, loss and delayed buffered replies during injection are preserved in the raw traces and summarized in `ping-summary.json`; these are simulator observations, not a hardware failover SLA.

A was destroyed after the 2026-10-09 tests; B was left deployed with all eight containers running at that time. Windows/WSL ownership was adjusted so the user can edit the topologies and configs from VS Code. The private license remains local and is excluded from the public repository. The separate 2026-10-12 direct-Arista-spine test is described in [Lab 3 validation](lab3-validation.md).

## Scope

These tests cover IPv4 unicast and the ARP/BUM behavior needed for the L2 check. They do not cover IPv6, production scale, ASIC performance, QoS, optics, hardware redundancy timing, access multihoming, host mobility or maintenance-release qualification.
