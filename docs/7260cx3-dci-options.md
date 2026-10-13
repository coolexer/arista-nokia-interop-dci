# DCI choices with Arista 7260CX3 spines

Assessment date: **2026-10-12**. Physical design: two Arista spines, two transparent Ethernet/DWDM circuits, two Nokia X1b BLs, routed fabric uplinks and a local Nokia BL interlink. The Lab 3/4 base topology has no direct Arista spine interlink or separate Arista-site border-leaf pair. Lab 5 adds an Arista MLAG peer-link for native Ethernet DCI.

**The established choice is end-to-end EVPN-VXLAN over an IP DCI, as tested in Lab 3. Plain L3 EVPN RT-5 gateway works in the cEOS probe. Full L2 multi-domain stitching and VXLAN-MPLS interworking are excluded for these 7260CX3 spines by Arista's published platform matrix.**

## Hardware documentation

The [7260X3 datasheet](https://www.arista.com/assets/data/pdf/Datasheets/7260X3_Datasheet.pdf) identifies 7260CX3 as part of this family. The interactive [Arista Supported Features matrix](https://www.arista.com/en/support/product-documentation/supported-features) was filtered to Fixed / **7260X3**, with the relevant categories expanded. The page states coverage through EOS 4.35.0F; this is not a check of the unknown customer maintenance release.

| Capability | Published family status | Consequence for this topology |
|---|---|---|
| IP multipath, BFD and routing VRFs | Supported | Routed DCI and VRF-lite are candidates |
| VXLAN bridging/routing and routing in overlay VRFs | Supported | Ordinary VTEP operation is available |
| IPv4/IPv6 EVPN IP-prefix routes | Supported | RT-5 is available; the lab checks IPv4 |
| EVPN Ethernet-segment all-active VXLAN multihoming | Unsupported | Do not assume ESI-based leaf/gateway redundancy |
| VXLAN-to-VXLAN all-active inter-domain gateway | Unsupported | Full hierarchical L2/L3 gateway design is excluded |
| EVPN L2 DCI gateway | Unsupported | This is distinct from forwarding leaf-to-leaf VXLAN through an IP spine |
| VXLAN-MPLS service interworking and MPLS EVPN services | Unsupported | The current Option B gateway role cannot move onto 7260CX3 |
| D-PATH processing | Unsupported | Do not transfer a D-PATH gateway design to these spines |
| IS-IS SR TI-LFA | Unsupported | Do not promise this transport repair mechanism on 7260CX3 |
| Plain RT-5 next-hop-self gateway | No separate matrix entry | Software-tested below; exact physical SKU/release qualification remains open |

See the [saved official VXLAN matrix view](references/arista-7260x3-vxlan-matrix.png). Advanced MPLS service restrictions do not mean every basic label operation is absent. The matrix separately lists basic label functions; those do not supply EVPN service termination or VXLAN-MPLS stitching.

The [Arista multi-domain overview](https://arista.my.site.com/AristaCommunity/s/article/Troubleshooting-Multi-Domain-EVPN-and-DCI) distinguishes L3-only RT-5 gateway from L2/L3 gateway models and their supported platforms. [The feature introduction](https://www.arista.com/en/support/toi/eos-4-25-0f) describes received RT-5 next-hop-self, introduced with EOS 4.25.0F. Basic RT-5 support alone is not proof of every inter-domain gateway function.

## All relevant service architectures

| Architecture | L2 / L3 | Spine role and required changes | Verdict with the current topology |
|---|---|---|---|
| End-to-end EVPN-VXLAN over routed IP | Both | Keep spines and Nokia BLs as IP transit; leaf VTEPs exchange EVPN | **Preferred for combined L2/L3.** Lab 3 validated services, MTU and eight single faults |
| VRF-lite with per-tenant eBGP | L3 | Make spines ordinary local VTEPs/VRF routers; use separate tenant interfaces/VLANs and eBGP across DCI | **Software-tested as the L3 component of Lab 5.** Requires fabric termination and per-VRF configuration, not just underlay BGP |
| VRF-lite for L3 + end-to-end VXLAN for selected L2 VNIs | Both, selectively | Combine tenant IP handoffs with a separate transport network for stretched L2 | **Feasible candidate.** Same cabling, more configuration; no full L2 gateway stitching. Not tested |
| Plain L3 EVPN gateway, VXLAN-to-VXLAN | L3 | Spine terminates tenant VXLAN and advertises received RT-5 with its own VTEP next hop | **Works on available cEOS.** Hardware gateway feature/SKU/maintenance-release sign-off remains open; independent L2 mechanism is needed |
| L3 gateway plus end-to-end VXLAN for selected L2 VNIs | Both, selectively | RT-5 uses gateways; L2 bypasses them using leaf-to-leaf EVPN/VXLAN reachability | **Conditional candidate.** L3 component tested; combined L2 bypass not tested. It retains remote VTEP exposure for L2 |
| Multi-domain L3 VRF with separate local/remote RD/RT identities | L3 | A different EVPN gateway feature, with domain-specific service identities | **Not qualified on 7260CX3.** Do not infer it from the plain RT-5 test; requires explicit feature/platform confirmation |
| Full hierarchical VXLAN-to-VXLAN L2/L3 gateway, including MLAG/anycast/ESI variants | Both | Spines must re-originate and terminate inter-domain L2 services as well as L3 | **Excluded for this model.** Published L2 DCI/gateway limits apply; MLAG alone does not add stitching support |
| VXLAN-to-EVPN-MPLS gateway / original Option B | Both | Spines become service PEs, with MPLS interworking | **Excluded for this model.** Keep suitable service BLs or choose a documented gateway platform |
| Direct EVPN-MPLS, LDP pseudowires or VPLS service termination | Depends on service | MPLS service PE on the Arista side | **Excluded for this model** by the relevant EVPN/MPLS service feature limits; basic MPLS transit is insufficient |
| Native Ethernet VLAN trunk across DWDM | L2; L3 needs separate routing | Change selected leaf-spine/BL handoffs to bridging; explicitly build a loop-free or single-active L2 path | **Lab 6 validates independent spines with Nokia single-active/LACP standby and shared L2/L3 trunks.** Lab 5 tests an alternative implementation: Arista MLAG plus Nokia EVPN all-active, with an added peer-link; VLAN 10 and VRF-lite VLAN 901 share both DCI channels. L2 redundancy uses LACP/EVPN, not IP ECMP. Transient loss/duplicate limitations are recorded |

The VRF-lite variants can use a global routing table for a single non-overlapping service, but multiple tenants or overlapping addressing require separate VRFs. A native VLAN alternative must prevent loops across both fabrics; activating both DCI trunks without a validated loop-prevention/redundancy design is not an acceptable solution.

Changing eBGP to OSPF/IS-IS in the IP underlay, or changing the EVPN peer/RR arrangement, changes transport/control-plane design rather than creating a new L2/L3 DCI service. The available transparent DWDM needs neither MPLS nor a service gateway for the Lab 3 architecture. Additional GRE/IPsec transport would need a specific requirement and endpoint support; it is not required by this topology.

## Plain L3 gateway: observed cEOS result

[Lab 4](../labs/lab4-arista-l3-gateway) uses the same eight nodes / eleven links and the available cEOS 4.34.7M engineering build plus SR Linux 26.7.1. Arista spines are gateways; Nokia BLs remain IP transit, and the Nokia leaf is the remote VTEP. This does not test a Nokia VXLAN-to-VXLAN multi-instance gateway.

| Check | Observed result |
|---|---|
| Received RT-5 next-hop-self command | Accepted and present in running BGP config |
| Access leaf EVPN relationships | Two local-gateway peers; no direct leaf-to-leaf session |
| Direct remote-leaf IP reachability | Absent in both access leaf underlays |
| Arista tenant route to 192.168.30.0/24 | Two gateway VTEPs: 10.255.1.254 and 10.255.1.253 |
| Nokia tenant route to 192.168.20.0/24 | The same two gateway VTEPs |
| L3, both directions | 5/5 replies with 0% steady-state loss |
| DF inner IP MTU 1500 | 3/3 replies in both directions |
| Fabric capture | VXLAN between Arista leaf and spine VTEPs |
| DCI capture | VXLAN between spine VTEPs and Nokia leaf; no Arista-leaf-to-Nokia-leaf VXLAN |
| L2 test | Expected failure; RT-2/RT-3 are filtered at the gateways |
| Each gateway paused separately | Bidirectional L3 recovered with the gateway still paused |
| Each DCI disabled separately | Bidirectional L3 recovered with the port still disabled |
| Final restoration | Both leafs again use both gateway next hops; bidirectional L3 passed |

An explicit **BGP router-id in TENANT** was necessary because these gateways have no tenant SVI address from which EOS can select one. The corrected public startup configs include it. The test preserves the original RD/RT, uses VNI 50000 on both VXLAN legs, and relies on distinct ASNs/AS-path loop prevention. It does not test RD/RT translation or D-PATH.

This is **two independent RT-5 gateways with L3 ECMP**, not an ESI all-active multihoming gateway. The matrix's negative all-active Ethernet-segment entries should not be confused with the observed BGP next-hop multipath. Conversely, the cEOS multipath result cannot override a hardware matrix restriction or qualify an ASIC.

[Raw evidence](results/lab4) includes route attributes, FIBs, separate fabric/DCI captures, fault-present routes, control-plane restoration and final probes. Four single faults passed. Continuous ping traces preserve transient loss/delay; no hardware convergence SLA is claimed.

Lab 4 was stopped after validation. Lab 3 was restored with its original IP-transit configuration.

## Choice by service boundary

1. **L2/L3 with local leaf VTEP addresses and active/standby DCI:** use [Lab 6](../labs/lab6-single-active-dci). Independent Arista VTEPs connect by standalone LACP LAGs to Nokia single-active BLs. Include the tested local fabric protection and qualify the full multi-site VLAN/VNI graph.
2. **L2/L3 with inter-site leaf VTEP reachability allowed:** use Lab 3's end-to-end EVPN-VXLAN over routed IP, with per-flow ECMP and BFD.
3. **L3-only EVPN gateway:** Lab 4 provides cEOS functional evidence. Resolve exact SKU, EOS release and hardware feature applicability before production use.

## Shared native Ethernet DCI

[Lab 5](../labs/lab5-shared-ethernet-dci) terminates each local fabric on ordinary VTEPs and exchanges native L2 Ethernet plus VRF-lite IPv4 across shared DCI trunks. Arista MLAG and Nokia EVPN all-active provide the distributed attachment; an Arista peer-link and independent management heartbeat are required. Leaf VTEP addresses stay local. This does not require the unsupported hierarchical VXLAN-to-VXLAN L2 gateway feature. [Software validation and limitations](lab5-validation.md) include all nine fault cases, an extended dual-primary guard test, and transient duplication during a spine rejoin. Physical SKU/EOS qualification remains required.


## Shared channels without Arista spine MLAG

[Lab 6](../labs/lab6-single-active-dci) uses Nokia EVPN single-active/LACP standby and ordinary one-member LAGs on independent Arista spines. It preserves local VTEP addresses and gives both L2 and L3 one active common DCI trunk with one standby. It does not require Arista ESI all-active or hierarchical L2 VXLAN stitching. [Validation](lab6-validation.md) covers 15 fault-present scenarios, MTU, broadcast delivery and a clean source deployment. Lab 5 remains an alternative that explicitly introduces spine MLAG.
