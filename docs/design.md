# Configuration and acceptance details

## Common topology

| Segment | Endpoint 1 | Endpoint 2 |
|---|---|---|
| DC1 leaf ↔ border leaf | 100.64.1.0/31 | 100.64.1.1/31 |
| DCI | 100.64.12.0/31 | 100.64.12.1/31 |
| DC2 border leaf ↔ leaf | 100.64.2.0/31 | 100.64.2.1/31 |
| VTEP loopbacks | DC1 leaf 10.255.1.1/32 | DC2 leaf 10.255.2.1/32 |
| Gateway loopbacks | DC1 BL 10.255.1.254/32 | DC2 BL 10.255.2.254/32 |

A uses management subnet 172.31.247.0/24; B uses 172.31.248.0/24. Hosts attach via separate eth1 (L2) and eth2 (L3) links, with IP forwarding disabled. Host L3 routes point to the local gateway `.1`. There are no spines, route reflectors or redundant border leafs.

## Option A

Both leafs use AS 65000 with a direct iBGP EVPN session. Border-leaf ASNs are 65201/65202. IPv4 underlay filters permit only the four loopbacks. Since both leafs share an ASN, their underlay neighbors allow one own-AS occurrence; this is a deliberate simplification for the small linear lab. Border leafs do not enable own-AS acceptance.

| Service | VNI | RT |
|---|---|---|
| L2 MAC-VRF / VLAN 10 | 10010 | 65000:10010 |
| TENANT IP-VRF | 50000 | 65000:50000 |

SR Linux advertises gateway MAC for EVPN IFL/IFF unnumbered interoperability. Arista's remote RT-5 is expected to include the router MAC, VNI 50000 and a zero gateway overlay index. EVPN next hops remain the leaf VTEPs across the IP DCI.

## Option B

Leaf ASNs are 65101/65102. Both gateways use AS 65000. Each fabric has local IPv4 eBGP and a separate loopback EVPN eBGP session (multihop 2). The DCI has iBGP EVPN plus IS-IS Level 2 / SR-MPLS. IS-IS advertises only the configured DCI/system interfaces, with no BGP redistribution.

| Service | Local VXLAN RT | DCI MPLS RT | Gateway instances |
|---|---|---|---|
| L2-10 | 65000:10010 | 65000:20010 | 1 access/VXLAN, 2 network/MPLS |
| TENANT | 65000:50000 | 65000:60000 | 1 access/VXLAN, 2 network/MPLS |

Gateway MAC-VRFs have no access or IRB subinterfaces. Gateways use different RDs per service/instance. D-PATH domains are 65000:1 (DC1), 65000:2 (DC2) and 65000:100 (DCI). Export policies select the appropriate encapsulation and add site SOO; import policies reject local SOO.

SRGB: 16000–16999; node SID indices 1/2. Dynamic label blocks: adjacency 20000–20999, EVPN 21000–21999, service 22000–22999, BUM 30000–30999. Allowed transport is SR-ISIS. On the direct two-gateway link, PHP can leave only a service label in the packet capture; this topology does not test a transit P-router.

## Acceptance checklist

1. Confirm image versions, X1b chassis type, license acceptance and clean startup configuration.
2. Confirm expected BGP sessions and, for B, the IS-IS adjacency and SR tunnels.
3. Confirm remote MAC/RT-3 state and remote tenant RT-5 prefixes.
4. Confirm both directions of L2/L3 ping and DF MTU 1500, with no loss after convergence.
5. Confirm encapsulation and next-hop ownership on each segment.
6. Change one import RT at a time: only that service must fail. Restore it and wait for convergence.
7. Disable the DCI port: both services must fail. Restore it and verify both again.

For RT changes, delete the complete old import-RT list before setting the new one. A uses instance 1 on the DC2 leaf; B uses MPLS instance 2 on the DC2 gateway. Restore the RT values from the table. Do not count a CLI/tooling error as a successful negative service test.
