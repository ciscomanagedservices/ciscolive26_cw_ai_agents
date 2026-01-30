# Network Diagram

The lab topology consists of Cisco CSR1000v routers, a Splunk server, ThousandEyes agent, Cisco CX RADKit, and a Cisco Workflows remote appliance. 

<figure markdown>
  ![Lab Topology](./img/topology.png)
</figure>

## Network Details

* Rotuers are CSR 1000v routers, setup to route an access network across themselves and out the Internet.

* **ubuntu-wkstn** routes out through the 198.18.1x.x network, so we can use R2 as a traffic congestion point. 

* **thousandeyes** agent sits on the access network, so it can run synthetic app user experience tests across the 198.18.1x.x network.

* **wf-remote** is a remote appliance that registers to Cisco Workflows, enabling Cisco Workflows to communicate with devices in a restricted network (no inbound access).

* Cisco CX **RADKit**- A ubuntu server that hosts Cisco CX RADKit for remote access, wrapped in an MCP server.

