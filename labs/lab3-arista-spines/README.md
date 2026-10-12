# Lab 3: direct DCI from Arista spines

Option A with the Arista site's Nokia border leafs removed. Two **transit-only Arista cEOS spines** connect directly to two Nokia X1b border leafs over independent routed Ethernet/DWDM circuits. The VTEPs and tenant gateways remain on the access leafs.

![Direct-spine DCI](../../docs/images/option-3.png)

**8 nodes / 11 links:** three Arista cEOS nodes, two Nokia X1b BLs, one Nokia D2L leaf, two Linux clients. There is no direct Arista spine-to-spine link. Each leaf has two routed uplinks; the Nokia BLs have a local interlink.

## Protocols and addressing

| Node | Loopback / VTEP | ASN | Role |
|---|---|---|---|
| dc1-leaf | 10.255.1.1 | 65101 | Arista VTEP / tenant gateway |
| dc1-spine1 | 10.255.1.254 | 65201 | IP transit, direct DCI-1 |
| dc1-spine2 | 10.255.1.253 | 65211 | IP transit, direct DCI-2 |
| dc2-bl | 10.255.2.254 | 65202 | Nokia X1b IP transit |
| dc2-bl2 | 10.255.2.253 | 65212 | Nokia X1b IP transit |
| dc2-leaf | 10.255.2.1 | 65102 | Nokia VTEP / tenant gateway |

IPv4 eBGP underlay uses BFD and up to two ECMP paths. Policies permit only these six loopbacks. Unique leaf ASNs retain normal AS-loop protection without an `allowas-in` exception. A direct loopback-to-loopback eBGP EVPN session, multihop 8, exchanges the leaf routes. This is the minimum control-plane arrangement for the two-leaf test; it does not model the customer's route reflectors.

The spines have no Vxlan1 interface, tenant VRF, MAC-VRF or EVPN gateway. They route the outer IP packets. DCI-1 is 100.64.12.0/31, DCI-2 is 100.64.12.2/31. Other link addressing follows [Option A](../../docs/design.md).

L2 uses VNI 10010 / RT 65000:10010, with client addresses 192.168.10.11 and .12/24. L3 uses VNI 50000 / RT 65000:50000 and symmetric IRB. The routed clients are in separate local subnets: 192.168.20.11/24 and 192.168.30.12/24; those access subnets are not L2 stretched.

## Run

Use the authorized local image tags and license procedure in the [main README](../../README.md). The failure script also requires `jq`. No images, license keys or distribution links are provided. Run labs sequentially when WSL memory is limited.

```bash
cd labs/lab3-arista-spines
# Place your X1b license in ./srl.license (ignored by Git).
chmod 600 srl.license
./preflight.sh
sudo containerlab deploy --topo interop-dci-3.clab.yml
# Wait for all NOS nodes and BGP/BFD sessions to become ready.
./verify.sh all
./bum.sh
./failover.sh
./isolation.sh
sudo containerlab destroy --topo interop-dci-3.clab.yml
```

The fault script pauses each spine and each Nokia BL separately, disables each DCI separately while the spine stays running, and disables one uplink on each leaf. It checks both services in both directions, flushes endpoint ARP and checks recovery while the fault remains present. It restores the fault and waits for all six NOS control planes before the next case. Continuous ping traces and fault-present FIB snapshots are retained under `results/`.

TopoViewer annotations and an editable draw.io diagram accompany the YAML for the Containerlab VS Code extension. Arista nodes are grey, Nokia nodes blue.

## Qualification boundary

This uses the available **cEOS 4.34.7M** and **SR Linux 26.7.1** images. No physical 7260CX3 SKU or installed customer EOS release was supplied. cEOS verifies the protocol design; it does not emulate or qualify the 7260CX3 ASIC, hardware hashing, failover timing, optical modules, scale or maintenance-release defects. The transparent DWDM links are represented by veth pairs.

[Arista's 7260X3 datasheet](https://www.arista.com/assets/data/pdf/Datasheets/7260X3_Datasheet.pdf) documents BGP, ECMP and BFD, the functions required of the transit spines. The third lab does not use the VXLAN-MPLS gateway functions of Option B.
