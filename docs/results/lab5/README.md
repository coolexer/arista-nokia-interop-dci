# Lab 5 evidence

See [the validation report](../../lab5-validation.md) for acceptance criteria and limitations.

| Directory | Evidence |
|---|---|
| `final-health` | Restored running state: MLAG, BGP, FIB, BFD, Nokia ES and final clean pings |
| `traffic-final` / `bum-final` | Final startup configuration: shared VLAN payload, MTU and broadcast tests |
| `failover-spines-final` | Both spine freezes after the cEOS management-interface correction; loss and rejoin duplicates are retained |
| `peer-link-held-final` | Sustained peer-link failure: live management heartbeat, exactly one guarded peer, both services and broadcast delivery |
| `failover-initial` | First nine-case functional run; independent heartbeat/dual-primary assertions must use the final sustained test |
| `baseline` / `traffic` / `bum` | Initial service/control-plane observations and shared-channel packet sample |

Packet and CLI text is retained with trailing whitespace removed. No license file or distribution URL is included. Time windows are simulator samples and do not establish a hardware convergence bound.
