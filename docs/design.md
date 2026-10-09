# Configuration and acceptance details

## Common topology

| Segment | Endpoint 1 | Endpoint 2 |
|---|---|---|
| DC1 leaf ↔ border leaf | 100.64.1.0/31 | 100.64.1.1/31 |
| DCI-1 | 100.64.12.0/31 | 100.64.12.1/31 |
| DC2 border leaf ↔ leaf | 100.64.2.0/31 | 100.64.2.1/31 |
| DC1 leaf ↔ second BL | 100.64.1.2/31 | 100.64.1.3/31 |
| DC2 second BL ↔ leaf | 100.64.2.2/31 | 100.64.2.3/31 |
| DCI-2 | 100.64.12.2/31 | 100.64.12.3/31 |
| DC1 BL interlink | 100.64.101.0/31 | 100.64.101.1/31 |
| DC2 BL interlink | 100.64.102.0/31 | 100.64.102.1/31 |
| Second BL loopbacks | DC1 10.255.1.253/32 | DC2 10.255.2.253/32 |
| VTEP loopbacks | DC1 leaf 10.255.1.1/32 | DC2 leaf 10.255.2.1/32 |
| Gateway loopbacks | DC1 BL 10.255.1.254/32 | DC2 BL 10.255.2.254/32 |

A uses management subnet 172.31.247.0/24; B uses 172.31.248.0/24. Hosts attach via separate eth1 (L2) and eth2 (L3) links, with IP forwarding disabled. Host L3 routes point to the local gateway `.1`. Each site has two redundant BLs; there are no spines or route reflectors. See [redundancy details](redundancy.md).

## Option A

Both leafs use AS 65000 with a direct iBGP EVPN session. Border-leaf ASNs are 65201/65211 (DC1) and 65202/65212 (DC2). IPv4 underlay filters permit only the six loopbacks. Since both leafs share an ASN, their underlay neighbors allow one own-AS occurrence; this is a deliberate simplification for the small lab. Border leafs do not enable own-AS acceptance.

| Service | VNI | RT |
|---|---|---|
| L2 MAC-VRF / VLAN 10 | 10010 | 65000:10010 |
| TENANT IP-VRF | 50000 | 65000:50000 |

SR Linux advertises gateway MAC for EVPN IFL/IFF unnumbered interoperability. Arista's remote RT-5 is expected to include the router MAC, VNI 50000 and a zero gateway overlay index. EVPN next hops remain the leaf VTEPs across the IP DCI.

## Option B

Leaf ASNs are 65101/65102. All four gateways use AS 65000. Each fabric has local IPv4 eBGP and a separate loopback EVPN eBGP session (multihop 2). The DCI has iBGP EVPN plus IS-IS Level 2 / SR-MPLS. IS-IS advertises only the configured DCI/system interfaces, with no BGP redistribution. IPv4-only iBGP with next-hop-self on each local BL interlink provides backup reachability to the local leaf VTEP; its prefix policy permits only the local fabric loopbacks.

| Service | Local VXLAN RT | DCI MPLS RT | Gateway instances |
|---|---|---|---|
| L2-10 | 65000:10010 | 65000:20010 | 1 access/VXLAN, 2 network/MPLS |
| TENANT | 65000:50000 | 65000:60000 | 1 access/VXLAN, 2 network/MPLS |

Gateway MAC-VRFs have no access or IRB subinterfaces. L3 uses unique RDs per gateway/instance; L2 uses shared RD and originating-IP per site/instance to implement Nokia gateway redundancy. D-PATH domains are 65000:1 (DC1), 65000:2 (DC2) and 65000:100 (DCI). Export policies select the appropriate encapsulation and add site SOO; import policies reject local SOO.

SRGB: 16000–16999; node SID indices 1/3 (DC1) and 2/4 (DC2). Dynamic label blocks: adjacency 20000–20999, EVPN 21000–21999, service 22000–22999, BUM 30000–30999. Allowed transport is SR-ISIS. On a direct gateway path, PHP can leave only a service label in the capture. A failed DCI link can use other gateways as SR-MPLS transit nodes over the local interlinks and surviving circuit.

## Acceptance checklist

1. Confirm image versions, X1b chassis type, license acceptance and clean startup configuration.
2. Confirm expected BGP sessions and, for B, the IS-IS adjacencies, BFD sessions and SR tunnels.
3. Confirm remote MAC/RT-3 state and remote tenant RT-5 prefixes.
4. Confirm both directions of L2/L3 ping and DF MTU 1500, with no loss after convergence.
5. Confirm encapsulation and next-hop ownership on each segment.
6. Change one import RT at a time: only that service must fail. Restore it and wait for convergence.
7. Run `./failover.sh`: pause each BL and disable each DCI/uplink individually; both services must recover while the fault remains, including fresh ARP. Restore each fault and verify again.
8. Disable both DCI circuits to test full isolation; restore them and check convergence and ECMP.

For RT changes, delete the complete old import-RT list before setting the new one. A uses instance 1 on the DC2 leaf; B uses MPLS instance 2 on both DC2 gateways. Restore the RT values from the table. Do not count a CLI/tooling error as a successful negative service test.
