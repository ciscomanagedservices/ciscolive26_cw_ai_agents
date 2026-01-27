# Network Diagram

The lab topology consists of Cisco CSR1000v routers, a Splunk server, ThousandEyes agent, and a Cisco Workflows remote appliance.

<figure markdown>
  ![Lab Topology](./img/topology.png)
</figure>

## Network Details

* **ubuntu-wkstn** routes out through the 198.18.1x.x network, so we can use R2 as a traffic congestion point if desired. This can also serve as a jumphost to other devices on the management network.

* **thousandeyes** agent sits on the access network, so it can run synthetic app user experience tests across the 198.18.1x.x network.

* **wf-remote** is a remote appliance that registers to Cisco Workflows, enabling Cisco Workflows to communicate with devices in a restricted network (no inbound access).

