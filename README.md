# Arista + Nokia interop and DCI

Reproducible Containerlab examples for **Arista cEOS 4.34.7M ↔ Nokia SR Linux 26.7.1**, connecting Layer 2 and Layer 3 services across two data centers.

Each lab has **6 nodes / 7 links**: an Arista leaf, a Nokia leaf, two Nokia IXR-X1b border leafs, and two Linux clients. The transparent Ethernet/DWDM connection is represented by a veth link.

| Lab | DCI architecture | Border-leaf role | Validation |
|---|---|---|---|
| [Option A](labs/option-a) | End-to-end EVPN-VXLAN over routed IP | IP transit | L2/L3, MTU, RT isolation and DCI outage tested |
| [Option B](labs/option-b) | Local VXLAN fabrics + EVPN-MPLS over SR-MPLS | Service gateway | L2/L3, MTU, RT isolation and DCI outage tested |

## Option A — end-to-end VXLAN

![Option A topology](docs/images/option-a.png)

Leaf VTEPs exchange EVPN directly. X1b border leafs route outer IP packets and do not terminate tenant services. L2 uses VNI 10010 and EVPN RT-2/RT-3; L3 uses VNI 50000, EVPN RT-5 and symmetric IRB. Only the selected VTEP/control-plane loopbacks cross the IP underlay.

## Option B — gateway stitching

![Option B topology](docs/images/option-b.png)

The X1b gateways terminate each local VXLAN fabric. A multi-instance MAC-VRF stitches L2 to EVPN-MPLS; a separate IP-VRF stitches L3 using two EVPN IFL instances, `allow-export` and D-PATH. The DCI runs IS-IS + SR-MPLS. Leaf VTEPs are kept within their respective fabrics.

## Run a lab

Prerequisites: Linux or WSL2, Docker, Containerlab, locally available NOS images, and an SR Linux license suitable for X1b emulation. This repository contains configuration examples; **it contains no license keys, NOS images, registry addresses or distribution links**.

Tag your authorized local images as follows:

```bash
docker tag <your-local-ceos-image> arista_ceos:4.34.7M
docker tag <your-local-srlinux-image> srlinux:26.7.1
docker tag <your-local-network-multitool-image> network-multitool:latest
```

Then choose A or B:

```bash
git clone https://github.com/coolexer/arista-nokia-interop-dci.git
cd arista-nokia-interop-dci/labs/option-a
# Place your license in ./srl.license; it is ignored by Git.
chmod 600 srl.license
chmod +x preflight.sh verify.sh configs/host-init.sh
./preflight.sh
sudo containerlab deploy --topo interop-dci-a.clab.yml
# After startup configuration and BGP convergence:
./verify.sh all
```

For B, use `labs/option-b` and `interop-dci-b.clab.yml`. `verify.sh l2` and `verify.sh l3` run individual service checks. `preflight.sh` validates files and local prerequisites without deploying or pulling images. Run the labs sequentially when WSL memory is limited.

```bash
sudo containerlab destroy --topo interop-dci-a.clab.yml
```

## Explore the topologies

Open the repository in VS Code with the Containerlab extension. Select **Graph (TopoViewer)**: both YAML files have companion `.annotations.json` files with fixed positions, data-center groups and vendor colors. The editable `.clab.drawio` diagrams use the generator invoked by the extension's **Graph (draw.io, Horizontal)** action and the Nokia Modern theme. Arista is grey; Nokia is blue.

## Test design and evidence

The L2 clients share `192.168.10.0/24`. The L3 clients use separate local subnets, `192.168.20.0/24` and `192.168.30.0/24`; those VLANs/BDs have no stretched L2 VNI. This makes the routed test distinct from the L2 test.

`verify.sh` collects control-plane state and checks bidirectional ICMP, inner IP MTU 1500 with DF set, and the encapsulation on the DCI. B additionally captures VXLAN inside both fabrics and MPLS on the DCI. Review imported routes and next hops as well as the PASS message.

- [Validation report](docs/validation.md)
- [Selected Option A CLI and traffic evidence](docs/results/option-a)
- [Selected Option B CLI and traffic evidence](docs/results/option-b)
- [Configuration and acceptance details](docs/design.md)

The tested cEOS image reports an **engineering build** of 4.34.7M. Container software forwarding demonstrates protocol interoperability; it does not qualify X1b ASIC performance, production scale, redundancy or DWDM optics. This is an independent lab example, not a vendor certification.

## Documentation

- [Nokia SR Linux 26.7 — EVPN L2](https://documentation.nokia.com/srlinux/26-7/books/vpn-services/evpn-vxlan-tunnels-layer-2.html)
- [Nokia SR Linux 26.7 — EVPN L3](https://documentation.nokia.com/srlinux/26-7/books/vpn-services/evpn-vxlan-tunnels-layer-3.html)
- [Nokia SR Linux 26.7 — inter-domain services and D-PATH](https://documentation.nokia.com/srlinux/26-7/books/vpn-services/inter-domain-vpn-services.html)
- [Nokia SR Linux 26.7 — SR-MPLS with IS-IS](https://documentation.nokia.com/srlinux/26-7/books/advanced-solutions/acg2086-mpls-sr-isis.html)
- [Arista — VXLAN/EVPN sample configurations](https://www.arista.com/en/um-eos/eos-sample-configurations)
- [Containerlab VS Code extension](https://containerlab.dev/manual/vsc-extension/)
