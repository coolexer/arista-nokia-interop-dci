# Validation report

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

Selected [raw CLI/capture evidence](results/option-a) has neutralized lab names. The configuration topology is the same; public files use local image tags instead of registry-qualified names. No software distributions or license keys are included.

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

## Scope

These tests cover IPv4 unicast and the ARP/BUM behavior needed for the L2 check. They do not cover IPv6, production scale, ASIC performance, QoS, optics, redundant gateways, multihoming, host mobility or maintenance-release qualification.
