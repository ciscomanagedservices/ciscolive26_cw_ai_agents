# Cisco Live EMEA 2026 - Agentic AI for Network Operations

**Cisco Workflows AI Agents Lab**

A 4-hour instructor-led lab at Cisco Live EMEA Amsterdam demonstrating how to build agentic AI-driven network operations using Cisco Workflows, ThousandEyes, and CX RADKit.

## Overview

This lab guides participants through building an end-to-end agentic network operations pipeline—from event detection through AI-driven troubleshooting and automated remediation. You'll progress from basic notification workflows to fully autonomous AI agents that can diagnose and resolve network issues.

### Architecture

```
Device Events → Splunk/ThousandEyes → Cisco Workflows → AI Agent → RADKit → Device Remediation
```

## Labs

### Lab 1: Setting up Network Topology
Configure the foundational infrastructure for agentic network operations:
- Access dCloud lab environment
- Configure router syslog forwarding to Splunk
- Set up Splunk webhooks to trigger Cisco Workflows
- Build a basic notification workflow with Webex Teams integration

### Lab 2: Automated Response with Cisco Workflows
Build rule-based remediation workflows for closed-loop automation:
- Register a Cisco Workflows Remote Server for device connectivity
- Configure terminal targets and target groups
- Create automated remediation workflows (interface unshut)
- Parse webhook payloads and dynamically select target devices

### Lab 3: Agentic AI with RADKit Integration
Import and configure the AI agent for cognitive troubleshooting:
- Import the agentic AI workflow into Cisco Workflows
- Install and configure RADKit with MCP server integration
- Connect the AI agent to interface shutdown events
- Observe AI-driven analysis and remediation recommendations

### Lab 4: ThousandEyes Integration for Digital Experience Monitoring
Extend agentic response with ThousandEyes observability:
- Register and configure a ThousandEyes Enterprise Agent
- Set up HTTP Server tests and alert rules
- Integrate ThousandEyes webhooks with Cisco Workflows
- Trigger AI-driven troubleshooting from network performance degradation
- Observe end-to-end root cause analysis and automated remediation

## Repository Structure

```
├── cfg/                    # Router configurations (R1, R2, R3)
├── lab-guide/              # MkDocs-based lab documentation
│   └── docs/               # Lab markdown files
├── scripts/                # Setup scripts
│   └── mcp-server/         # MCP server enrollment and setup
│   └── tools/              # Script to update JSON for AI agent tool list
│   └── radkit/             # Radkit setup--not needed for the lab
└── workflows/              # Cisco Workflows JSON exports
```

## Prerequisites

- Access to Cisco dCloud lab environment
- Cisco Workflows account (meraki.cisco.com)
- Webex account for bot integration
- ThousandEyes account (for Lab 4)

## Lab Guide

The full lab guide is available online at:

**🌐 [https://cl-ltr.ciscolabs.com/0361f55971/](https://cl-ltr.ciscolabs.com/0361f55971/)**

You can also serve the guide locally with MkDocs:

```bash
cd lab-guide
pip install mkdocs
mkdocs serve
```

## Authors

- **Scott Dozier** - Lab Developer
- **Steve Holl** - Lab Developer
- **Aman Sardana** - Contributor

## License

This project is intended for educational purposes as part of Cisco Live EMEA 2026.
