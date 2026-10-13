# Lab 6: independent Arista spines and Nokia single-active DCI

![Shared single-active trunks](images/option-6.png)

**Result: bidirectional L2 and L3 IPv4 passed, including 15 fault-present scenarios.** Independent Arista spine VTEPs use standalone one-member LACP LAGs. Nokia EVPN single-active/LACP standby selects one trunk carrying both services. There is no Arista spine MLAG or peer-link, and leaf VTEP addresses remain inside each local fabric.

Fault tests ran on **12 October 2026**. A clean deployment from the repository configuration and the final service/control-plane checks passed on **13 October 2026**, without additional NOS configuration commands. The lab was destroyed after verification.

## Tested software and topology

- 8 nodes / 11 links, with two independent Arista spine VTEPs, two Nokia X1b BLs, one leaf and one Linux client per site.
- cEOS `4.34.7M-48746980.4347M`, engineering build.
- Nokia SR Linux `v26.7.1`, build `554-g78ed635f70a`, with the BL containers reporting `7250 IXR-X1B` and the leaf `7220 IXR-D2L`.
- VLAN 10 carries the L2 service. VLAN 901 carries per-circuit /31 tenant eBGP/BFD transit. The access L3 networks are separate local VLANs/BDs and use local EVPN RT-5/IP-VRF forwarding.
- Separate BL ASNs retain inter-BL EVPN reachability through the Nokia leaf when the direct BL interlink fails.

## Service checks

| Check | Observed result |
|---|---|
| L2, both directions | PASS, steady probes without loss or duplicates |
| L3 IPv4, both directions | PASS, steady probes without loss or duplicates |
| Inner IP MTU 1500 with DF | PASS for L2 and L3 in both directions |
| Broadcast delivery | Exactly five ARP requests received for five sent, in each direction |
| Shared DCI encapsulation | VLAN 10 and 901 on the same active trunk, native Ethernet, no inter-site VXLAN |
| Leaf infrastructure separation | No remote leaf VTEP route in either site's default underlay |
| Standby signaling | Nokia LAG down with `standby-signaling`; peer Arista standalone port-channel inactive |
| Final state | Exactly one active LACP trunk and one active DCI BGP peer pair, both core guards healthy and all local Nokia BL peers restored |

[Initial protocol state and packet captures](results/lab6/initial-state), [post-fault control-plane restoration](results/lab6/post-fault-health), and [clean-start evidence](results/lab6/clean-start) retain the measurements.

## Fault tests

A PASS requires L2 and L3 in both directions **while the fault is held**, followed by fresh ARP checks and service restoration. Traces contain both fault and recovery intervals when those fall within the capture window. Each fault is restored before proceeding.

| Scenario | Stable fault-present L2/L3 |
|---|---|
| [DCI circuit 1 disabled](results/lab6/dci1/test.log) | PASS |
| [DCI circuit 2 disabled](results/lab6/dci2/test.log) | PASS |
| [Arista spine 1 fabric uplink disabled](results/lab6/arista-uplink1/test.log) | PASS |
| [Arista spine 2 fabric uplink disabled](results/lab6/arista-uplink2/test.log) | PASS |
| [Nokia BL1 leaf-facing uplink disabled](results/lab6/nokia-uplink1/test.log) | PASS |
| [Nokia BL2 leaf-facing uplink disabled](results/lab6/nokia-uplink2/test.log) | PASS |
| [Arista spine 1 NOS paused](results/lab6/pause-spine1/test.log) | PASS |
| [Arista spine 2 NOS paused](results/lab6/pause-spine2/test.log) | PASS |
| [Nokia BL1 NOS paused](results/lab6/pause-bl1/test.log) | PASS |
| [Nokia BL2 NOS paused](results/lab6/pause-bl2/test.log) | PASS |
| [Direct Nokia BL interlink disabled](results/lab6/nokia-peer/test.log) | PASS |
| [Nokia BL1 both core links disabled](results/lab6/nokia-core1/test.log) | PASS |
| [Nokia BL2 both core links disabled](results/lab6/nokia-core2/test.log) | PASS |
| [Nokia BL1 local EVPN group disabled, links retained](results/lab6/evpn-core1/test.log) | PASS |
| [Nokia BL2 local EVPN group disabled, links retained](results/lab6/evpn-core2/test.log) | PASS |

The Nokia native event handler monitors the two local EVPN peer sessions. If none is established, it operationally gates the DCI member. The physical-core and EVPN-only isolation cases exercise this protection. Arista link tracking disables the DCI member after loss of its tracked physical fabric uplink. That Arista mechanism covers physical-link isolation; loss of only its EVPN control plane while physical links and LACP remain healthy is outside this tested protection. A paused NOS preserves carrier and tests software liveness, rather than physical power loss.

## Transition observations

There were **no duplicate echo replies in the 60 continuous traces**. Transitions were not hitless. The largest observed inter-reply gap was **45.611 seconds**, during the `evpn-core1` L3 reverse trace. This is an observation of the container experiment and includes convergence and simulation/scheduling effects. It is not a hardware convergence bound or an outage upper bound: finite traces can finish before complete restoration. [Per-flow observations](results/lab6/trace-summary.json) and raw traces preserve the data.

BFD protects tenant L3 neighbors but does not itself switch an L2 ES. LACP standby makes the whole LAG inactive, including the routed transit subinterface; a newly active eBGP session must establish before L3 resumes. DF non-revertive behavior can retain the alternate path after recovery.

## Deployment boundaries

This is a two-site functional software interoperability result, not 7260CX3 ASIC emulation or vendor certification. Exact physical SKU/EOS feature applicability, scale, optical behavior and hardware timing still require qualification. IPv6 services and access-leaf/node redundancy were not exercised.

DWDM must transparently transport LACP PDUs and tagged frames. For a deployment involving two existing Arista sites and a new Nokia site, use a separate ES/LAG per independent Arista site and review the complete L2 service graph. **Avoid a parallel service path for the same VLAN/VNI through the existing Arista inter-site connection, including a VXLAN path.** Making those physical links routed does not eliminate a loop if the same VNI still bridges the sites over that IP transport. The required VLAN/VNI and route-target scope must be agreed for the whole deployment. The two-site lab does not qualify that three-site service graph.

The earlier `power-off` prototype was not selected for this software test: cEOS administrative shutdown does not propagate far-end carrier loss to the SR Linux veth peer. The selected LACP method detects loss of peer protocol liveness and was verified without an external carrier or failover controller. This observation does not invalidate optical power-off signaling on physical equipment.

[Configuration and run instructions](../labs/lab6-single-active-dci)
