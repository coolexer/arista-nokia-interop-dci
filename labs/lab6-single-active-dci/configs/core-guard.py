"""Gate the DCI member when all monitored local EVPN peers are unavailable."""
import json


def event_handler_main(payload):
    event = json.loads(payload)
    healthy = any(item.get("value") == "established" for item in event.get("paths", []))
    ports = event.get("options", {}).get("down-links", [])
    actions = [{"set-ephemeral-path": {"path": "interface " + port + " oper-state",
                                      "value": "up" if healthy else "down"}} for port in ports]
    return json.dumps({"actions": actions})
