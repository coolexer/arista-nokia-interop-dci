# Border-leaf redundancy

Both labs have two X1b border leafs per site, two independent routed leaf uplinks, two DCI circuits, and a routed interlink between the local BLs. Each leaf retains its own VTEP and distributed L3 gateway. The interlinks provide an alternate path when a DCI circuit fails, without requiring four DCI circuits.

| Mechanism | Option A | Option B |
|---|---|---|
| IP underlay | eBGP ECMP, up to two paths; different BL ASNs accepted for multipath | Local eBGP + local BL iBGP IPv4; IS-IS L2 in the gateway ring |
| Failure detection | Single-hop BFD on leaf, DCI and local BL links | Single-hop BFD for local BGP and IS-IS adjacencies |
| L3 services | End-to-end leaf EVPN; ECMP forwards the outer VXLAN packets | Two service-gateway next hops, unique IP-VRF RDs, EVPN ECMP 2 |
| L2 services | End-to-end leaf EVPN; same underlay protection as L3 | Same per-site RD and originating-IP for each L2 instance; BGP selects a gateway for each received NLRI |
| Loop prevention | AS-path checks; bounded own-AS exception on the two leaf underlay groups | Site SOO, encapsulation export filters, internal-tag guard, D-PATH for L3 |
| MPLS local repair | Not applicable | IS-IS TI-LFA link protection |

ECMP and BFD solve different problems: ECMP distributes flows across usable equal-cost paths; BFD detects a forwarding failure even when Ethernet carrier stays up. Use per-flow hashing to preserve packet order. SR Linux Option A also enables resilient hashing for the selected loopback prefix range; the container does not demonstrate ASIC hash behavior.

LAG/MLAG is unnecessary on these routed interconnections. EVPN Ethernet-segment multihoming is useful for dual-attached servers or access devices, but is a different function from multi-instance gateway redundancy. The lab has single access leafs and single-attached clients; those remain failure domains.

## Option A

Leafs remain in AS 65000. DC1 BL/BL2 use AS 65201/65211, and DC2 BL/BL2 use AS 65202/65212. Underlay eBGP allows up to two paths with different neighbor ASNs. The permitted prefixes are the two leaf VTEPs and four gateway loopbacks. BLs do not terminate VXLAN or tenant services. The leaf-to-leaf EVPN session can continue over the surviving IP path.

Both circuits are used when the leaf FIB contains two equal paths. Local BL links provide a longer AS-path backup after a circuit failure. This is not a claim that every BL prefix always has two equal next hops.

## Option B

All four gateways use AS 65000, with full-mesh iBGP EVPN. The IS-IS ring advertises gateway loopbacks only. Each local BL pair also exchanges the three permitted fabric loopbacks over a separate IPv4-only iBGP session on its physical interlink, with next-hop-self, BFD and an explicit interlink source address (iBGP otherwise defaults to the router-id on SR Linux). This preserves gateway-to-leaf VXLAN reachability if one local uplink fails. The DCI EVPN sessions keep IPv4 unicast disabled, so leaf VTEPs remain local to their DC. Each gateway has six BGP peers (local leaf underlay, local BL IPv4, local leaf EVPN, three gateway EVPN peers), while BGP and IS-IS share the BFD session on the local interlink. DCI links have metric 100 and local BL interlinks metric 10. Each gateway has a distinct loopback and node SID: DC1 BL/BL2 indices 1/3, DC2 BL/BL2 indices 2/4. TI-LFA protects the transport link; it cannot replace a failed service endpoint.

L3 gateway instances use distinct RDs on every gateway so that both service next hops remain visible. Both gateways in a DC share its fabric D-PATH domain (65000:1 or 65000:2); the MPLS domain is 65000:100. Both EVPN instances in each IP-VRF have `ecmp 2`, as does the Nokia leaf IP-VRF. The Arista BGP maximum-paths setting is 2.

For **L2**, Nokia's documented redundant gateway procedure requires shared identity within a redundancy group:

| Site | VXLAN RD | MPLS RD | Originating-IP, both instances |
|---|---|---|---|
| DC1 | 10.255.1.252:10 | 10.255.1.252:11 | 10.255.1.252 |
| DC2 | 10.255.2.252:10 | 10.255.2.252:11 | 10.255.2.252 |

These originating-IP values identify the L2 redundancy groups; they are not anycast forwarding VTEPs. Actual VTEPs remain .253 and .254. Both gateways reject their own site's SOO, tag routes imported by the VXLAN L2 instance, and filter encapsulations on export. Equivalent IMET/MAC routes are selected by BGP, preventing duplicate multicast destinations toward the redundant pair. This is not an all-active Ethernet Segment or a promise of two-way L2 service-gateway load balancing.

The lab also runs L3, which normally makes both gateway VTEPs known to the leafs. A future L2-only variant must address the source-VTEP security requirement documented by Nokia, for example through its suggested dummy MAC-VRF with unique RDs.

## Timers and tests

BFD requests 500 ms transmit/receive, multiplier 3. In the Option A simulator, operational state reports active transmit/receive intervals of 1 s despite the 500 ms configuration, giving nominal detection of 3 s. Use the negotiated operational values, rather than multiplying configuration values alone. These are conservative VM test settings, not a production convergence SLA. Inspect negotiated timers and all sessions before reducing them. IXR X1b uses software BFD according to Nokia's OAM guide. Forwarding repair and EVPN route selection add to failure-detection time.

Run `./verify.sh all`, `./bum.sh`, then `./failover.sh`. `bum.sh` sends five broadcast-only ARP requests and counts delivery at the remote client; exactly five must arrive. The latter freezes each gateway individually with `docker pause` (carrier stays up), disables each DCI port individually, and disables selected leaf uplinks. Each case checks bidirectional L2/L3 both with warm state and after endpoint ARP flush, then restores the fault and checks all three BFD sessions and expected BGP peers on the restored gateway. Timestamped continuous ping traces are saved under ignored `results/`. This test intentionally changes only the named lab containers. It restores a pending fault on exit.

For RT-isolation tests in a redundant service, apply the wrong RT to **both** members of the receiving gateway pair; changing one member merely tests failover. With either DCI link down, both services must remain available; with both DCI links down, both must fail. Allow BGP reconnection after restoration before checking full ECMP membership.

Two fibers in the same duct, two wavelengths on the same unprotected optical path, or two links sharing the same DWDM equipment do not provide independent circuit failure protection. This veth lab cannot test those physical dependencies.

## Sources

- [Nokia 26.7: multi-instance gateway redundancy and L3 interworking](https://documentation.nokia.com/srlinux/26-7/books/vpn-services/inter-domain-vpn-services.html)
- [Nokia 26.7: BGP multipath](https://documentation.nokia.com/srlinux/26-7/books/routing-protocols/bgp.html)
- [Nokia 26.7: BFD configuration and platform implementation](https://documentation.nokia.com/srlinux/26-7/books/oam/oam_fault_and_performance_tools_and_protocols.html)
- [Nokia 26.7: TI-LFA](https://documentation.nokia.com/srlinux/26-7/books/segment-routing/loop-free-alternates.html)
- [Arista: BGP ECMP](https://www.arista.com/en/um-eos/eos-border-gateway-protocol-bgp)

The running SR Linux release accepts these configuration paths. YANG platform lookup includes X1b for TI-LFA and resilient hashing. This is functional simulator validation, not hardware qualification or a statement that the release has no known issues.
