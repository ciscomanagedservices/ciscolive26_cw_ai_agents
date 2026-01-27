# Cisco Live 2026 - Agentic Operations with Cisco Workflows

## Repository Overview

This repository contains the lab guide content and workflow definitions for the Cisco Live 2026 session **"Agentic Operations with Cisco Workflows"** (LTRAI-1487).

### Purpose

This lab teaches participants how to build AI-powered network operations agents using Cisco Workflows, integrating with network infrastructure, observability tools, and Large Language Models for autonomous troubleshooting and remediation.

## Repository Structure

```
ciscolive26_cw_ai_agents/
├── lab-guide/              # MkDocs-based lab guide documentation
│   ├── docs/
│   │   ├── lab1.md        # Splunk & Webex integration
│   │   ├── lab2.md        # Workflow automation
│   │   ├── lab3.md        # AI Agent setup with RADKit
│   │   ├── lab4.md        # ThousandEyes integration
│   │   ├── lab5.md        # Custom tool creation
│   │   └── overview.md    # Lab introduction
│   └── mkdocs.yml         # MkDocs configuration
├── workflows/             # Cisco Workflows JSON exports
│   │                      # (Auto-committed by Cisco Workflows visual editor)
│   ├── ThousandEyes/     # ThousandEyes integration workflows
│   ├── ai/               # OpenAI chat completion workflow
│   ├── ai_agent/         # AI Agent and ToolBox workflows
│   └── mcp/              # MCP server tool workflows
└── scripts/              # Helper scripts for development
```

## Publishing Architecture

### Two-Repository System

1. **Source Repository** (this repo): `ciscolive26_cw_ai_agents`
   - Contains lab guide markdown files
   - Contains workflow JSON definitions
   - Managed by lab authors

2. **Publishing Repository**: `ltrai-1487-clemea26` (ciscodocs)
   - Contains full ciscodocs template (MkDocs Material theme)
   - Contains custom CSS styling and branding
   - Publishes to AWS S3 via GitHub Actions
   - Published site: https://cl-ltr.ciscolabs.com/0361f55971/

### Sync Workflow

The markdown files from this repository sync to the ciscodocs repository, where they are published with the full Cisco branding and styling.

---

## Recent Task: Lab Guide Emphasis Styling

### ✅ Task Complete!

Successfully updated all lab markdown files with emphasis styling and created a pull request.

## Files Updated (6 total)

| File | Lines | Status | Changes |
|------|-------|--------|---------|
| **lab1.md** | 270 | ✅ Complete | Splunk integration, Webex notifications |
| **lab2.md** | 148 | ✅ Complete | Workflow configuration, automation rules |
| **lab3.md** | 574 | ✅ Complete | RADKit setup, MCP server, AI Agent configuration |
| **lab4.md** | 165 | ✅ Complete | ThousandEyes integration, webhook setup |
| **lab5.md** | 355 | ✅ Complete | Custom tool creation, ToolBox integration |
| **overview.md** | 83 | ✅ Complete | Lab overview, credentials table |

## Styling Applied

Consistent emphasis classes throughout all files:

- 🔴 **`<em class="lab-warning">`** - UI components, field names, important settings
- 🟠 **`<em class="example-input">`** - Values/text users must enter  
- 🔵 **`<em class="button-click">`** - Buttons, navigation paths, clickable elements

## Example Transformation

### Before:
```markdown
1. Go to **Settings > Data > Indexes**
2. Set the **name** to `syslog`
3. Click **Submit**
```

### After:
```markdown
1. Go to <em class="button-click">Settings > Data > Indexes</em>
2. Set the <em class="lab-warning">name</em> to <em class="example-input">syslog</em>
3. Click <em class="button-click">Submit</em>
```

## Git Actions

- ✅ Created branch: `feature/add-emphasis-styling`
- ✅ Committed all changes with descriptive message
- ✅ Pushed to GitHub: https://github.com/ciscomanagedservices/ciscolive26_cw_ai_agents
- ✅ Opened PR creation page in browser

## Next Steps

The PR creation page is now open in your browser. You can:
1. Review the changes in the GitHub UI
2. Add any additional description or context
3. Create the pull request when ready

The changes will sync to the `ltrai-1487-clemea26` ciscodocs repository once merged, and the enhanced CSS styling will make all the colored emphasis classes visible on the published lab guide!

## CSS Classes Reference

These classes are defined in the ciscodocs repository (`ltrai-1487-clemea26`) at `docs/stylesheets/extra.css`:

```css
/* Red - for UI components and important settings */
em.lab-warning { color: #ff6b6b; font-style: normal; font-weight: 600; }

/* Orange - for text/values users must enter */
em.example-input { color: #f7a35c; font-style: normal; font-weight: 600; }

/* Blue - for buttons and clickable elements */
em.button-click { color: #5bc0eb; font-style: normal; font-weight: 600; }
```

## Published Site

Once the PR is merged and synced, the updated lab guide will be available at:
**https://cl-ltr.ciscolabs.com/0361f55971/**

