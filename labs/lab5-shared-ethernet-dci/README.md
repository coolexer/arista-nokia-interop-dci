# Lab 5: shared Ethernet DCI — Arista MLAG + Nokia EVPN all-active

Native Ethernet trunks carry **L2 VLAN 10 and L3 transit VLAN 901 on the same two DCI circuits**. Arista spines form an MLAG pair and terminate their local VXLAN fabric. Nokia X1b border leafs expose a common all-active Ethernet Segment. Inter-site EVPN and leaf VTEP routing are absent.

![Shared Ethernet DCI](../../docs/images/option-5.png)

**8 nodes / 12 links:** three cEOS nodes, two licensed SR Linux X1b BLs, one D2L leaf, two Linux clients. DWDM is represented by transparent veth pairs. Hosts and access leafs are single-attached; this lab tests DCI redundancy.

## Services

| Item | Configuration |
|---|---|
| DCI Ethernet | Arista Port-Channel100 / MLAG 100 ↔ Nokia lag1, fast LACP; VLAN 10 + 901 |
| L2 service | 192.168.10.11 ↔ .12; local VNI 10010, native VLAN 10 across DCI |
| L3 service | DC1 192.168.20.0/24 ↔ DC2 192.168.30.0/24; VRF TENANT |
| L3 transit | VLAN 901 / 10.200.0.0/29; Arista .1/.2, Nokia .3/.4 |
| L3 routing | Four eBGP adjacencies AS 65201 ↔ 65202, ECMP 2 + BFD 500 ms Ã— 3 |
| Arista MLAG | Ethernet3 / Port-Channel10 peer-link; VLAN 4094 peer SVI; management heartbeat and dual-primary detection |
| Arista VTEP | Shared spine VTEP 10.255.1.250; access leaf 10.255.1.1 stays local |
| Nokia redundancy | Common ESI, common LACP system ID/key, all-active; local VXLAN and two-path EVPN aliasing |

The L3 transit VLAN is a separate Nokia MAC-VRF with IRB on both BLs. **EVPN ARP advertisement/synchronization is required**: a peer's reply may arrive through the other BL and the local VXLAN fabric. Both BLs advertise dynamic ARP, learn unsolicited ARP on attachment circuits, and use ARP timeout 270 s. Without ARP synchronization, only the two directly paired BGP sessions became established in the initial lab.

X1b also requires an EVPN dynamic label pool for Ethernet Segment control-plane resources. This does not make the DCI an MPLS network: captured DCI packets are VLAN-tagged Ethernet.

Export policies permit only tenant service prefixes; they reject local fabric loopbacks. Each fabric runs EVPN independently. VLAN 901 is a shared multiaccess transit, not four point-to-point IP links.

## Run

Use authorized local image tags and an X1b license as described in the [main README](../../README.md). No images, registry URLs or license keys are included. Allow several minutes for simultaneous NOS startup.

```bash
cd labs/lab5-shared-ethernet-dci
# Put your local X1b license in ./srl.license (Git-ignored).
chmod 600 srl.license
chmod +x *.sh configs/host-init.sh
./preflight.sh
sudo containerlab deploy --topo interop-dci-5.clab.yml
./verify.sh
./bum.sh
./failover.sh
./peerlink.sh
sudo containerlab destroy --topo interop-dci-5.clab.yml
```

`verify.sh` checks both services in both directions, IP MTU 1500 with DF, both DCI trunks carrying both service VLANs, and absent remote-leaf routes. `bum.sh` counts broadcast ARP delivery. `failover.sh` injects one fault at a time, checks both services and fresh endpoint ARP with the fault present, and restores all four DCI BGP adjacencies before proceeding.

`peerlink.sh` additionally holds the peer-link down beyond the MLAG heartbeat timer, checks a live independent management heartbeat, exactly one peer guarded against dual-primary, and both services plus broadcast delivery. cEOS uses **Management0**; a Management1 configuration does not bind to the actual container management port.

TopoViewer annotations, an editable draw.io file and PNG/SVG views accompany the topology.

## Qualification boundary

cEOS **4.34.7M** and SR Linux **26.7.1** validate the software protocol design. cEOS does not emulate the 7260CX3 ASIC. Hardware LAG hashing, scale, optics, real failure timing and the exact customer's EOS release still require physical qualification. The Arista side uses MLAG, not EVPN ESI multihoming.

[Validation results](../../docs/lab5-validation.md)
