# Lab 3 - Creating a Cognitive AI Agent in Cisco Workflows

## Overview

In this lab, you will configure Cisco Workflows to act as an AI Agent that can respond, investigate, and remediate (with your approval) incoming events. By the end of this lab, you will have:

- Imported the AI Agent workflow definitions from GitHub
- Configured OpenAI API credentials for LLM access
- Connected the AI Agent to your existing webhook trigger
- Tested the cognitive agentic response to a network event

The event flow remains the same as Lab 1, but now with cognitive analysis:

```txt
device -> [syslog] -> splunk -> [webhook] -> Cisco Workflows -> [agentic analysis] -> device
```

However, the agentic response will be a series of LLM calls which trigger tools (sub workflows) until work is completed.

```txt
┌─────────────────────────────────────────────────────────────────┐
│                        AI Agent Workflow                        │
│                                                                 │
│   ┌─────────────────┐      ┌─────────────────────────────────┐  │
│   │  OpenAI Chat    │      │            ToolBox              │  │
│   │  Completion     │      │  ┌─────────────────────────┐    │  │
│   │                 │      │  │ execute_terminal_command│    │  │
│   │  - system prompt│      │  │ scratchpad_read/write   │    │  │
│   │  - tools JSON   │ ───▶ │  │ request_change_approval │    │  │
│   │  - messages     │ ◀─── │  │ webex_notification      │    │  │
│   │                 │      │  │ ask_clarifying_question │    │  │
│   └─────────────────┘      │  └─────────────────────────┘    │  │
│          │                 └─────────────────────────────────┘  │
│          │                                                      │
│          ▼                                                      │
│   ┌──────────────┐                                              │
│   │ Loop until   │                                              │
│   │ final answer │                                              │
│   └──────────────┘                                              │
└─────────────────────────────────────────────────────────────────┘
```

---

## Step 1: Import the Cognitive Response Workflows

We will need to import the cognitive response workflow definitions from GitHub into your Cisco Workflows instance.

> **Important:** You will create **3 separate Git repositories** in Cisco Workflows, each pointing to a different code path in the same GitHub repo. This organizes the workflows into logical groups.

```txt
┌─────────────────────────────────────────────────────────────────┐
│                    GitHub Repository Structure                   │
│                                                                  │
│   ciscolive26_cw_ai_agents/                                      │
│   └── workflows/                                                 │
│       ├── ai/              ◀── Repo 1: OpenAI Chat Completion   │
│       ├── ai_agent/        ◀── Repo 2: AI Agent + Tools         │
│       └── mcp/             ◀── Repo 3: MCP Server Integration   │
└─────────────────────────────────────────────────────────────────┘
```

### 1.1 Add Git Repositories to Cisco Workflows

1. Go to Meraki Dashboard on your workstation
2. Go to **Automation** -> **Workspace**
3. On the right, click the **Actions** button and then **Manage Git Repositories**

You will add **3 repositories** using the steps below. Each repository uses the same GitHub credentials but a different **Code Path**.

### 1.2 Repository 1: AI (OpenAI Chat Completion)

1. Click **New git repository**
2. Fill the repository details:
   - **Display Name:** `LTRAI-1487 - AI`
   - Click Default Account Keys -> **Add New** 
     - You may optionally use your GitHub username/password, but it's better to create a classic access token. If you do not have a GitHub access token, follow these steps: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens 
     - Username: `<your username>`
     - Password: `<token>`
   - **REST API Repository:** `api.github.com/repos/ciscomanagedservices/ciscolive26_cw_ai_agents`
   - **Branch:** `main`
   - **Code Path:** `workflows/ai`

### 1.3 Repository 2: AI Agent (Agent Workflow + ToolBox)

1. Click **New git repository** again
2. Fill the repository details:
   - **Display Name:** `LTRAI-1487 - AI Agent`
   - Use the same Account Keys you created in Repository 1
   - **REST API Repository:** `api.github.com/repos/ciscomanagedservices/ciscolive26_cw_ai_agents`
   - **Branch:** `main`
   - **Code Path:** `workflows/ai_agent`

### 1.4 Repository 3: MCP (Model Context Protocol)

1. Click **New git repository** again
2. Fill the repository details:
   - **Display Name:** `LTRAI-1487 - MCP`
   - Use the same Account Keys you created in Repository 1
   - **REST API Repository:** `api.github.com/repos/ciscomanagedservices/ciscolive26_cw_ai_agents`
   - **Branch:** `main`
   - **Code Path:** `workflows/mcp`

### 1.5 Verify Repository Configuration

Confirm that you have 3 Git repositories configured in Cisco Workflows:

| Display Name | Code Path |
|--------------|-----------|
| LTRAI-1487 - AI | `workflows/ai` |
| LTRAI-1487 - AI Agent | `workflows/ai_agent` |
| LTRAI-1487 - MCP | `workflows/mcp` |

### 1.6 Import Workflows

You will now import workflows from all three Git repositories. Follow the steps below in order, as some workflows depend on others.

> **Note:** When importing workflows, you may be prompted for credentials or API keys. Keep your OpenAI API key and Webex access token from earlier labs handy.

#### Import Order Overview

```txt
1. OpenAI Chat Completion (AI repo)          ← Core LLM interface
2. MCP Server Tools (MCP repo)               ← Tool execution layer
3. ToolBox (AI Agent repo)                   ← Tool registry (includes all tool subworkflows)
4. AI Agent (AI Agent repo)                  ← Main orchestrator
```

#### 1.6.1 Import OpenAI Chat Completion

1. Go to **Automation** -> **Workspace**
2. Click **Actions** -> **Import Workflow**, then click the **Git** tab
3. Select:
   - **Repository:** `LTRAI-1487 - AI`
   - **Workflow:** `OpenAIChatCompletion`
   - **Version:** Latest
4. Click **Import**
5. When prompted for `i_api_key`:
   - Enter your lab OpenAI API key
   - **Ask your instructor for this key if you don't have it**
6. Click **Import**

#### 1.6.2 Import MCP Server Tools

1. Click **Actions** -> **Import Workflow**, then click the **Git** tab
2. Import `MCPListTools`:
   - **Repository:** `LTRAI-1487 - MCP`
   - **Workflow:** `MCPListTools`
   - **Version:** Latest
   - Click **Import**
3. Import `MCPRunTool`:
   - **Repository:** `LTRAI-1487 - MCP`
   - **Workflow:** `MCPRunTool`
   - **Version:** Latest
   - Click **Import**

#### 1.6.3 Import ToolBox

The ToolBox workflow includes all tool subworkflows as embedded components, so you only need to import this single workflow to get all the tools.

1. Click **Actions** -> **Import Workflow** -> **Git** tab
2. Select:
   - **Repository:** `LTRAI-1487 - AI Agent`
   - **Workflow:** `ToolBox`
   - **Version:** Latest
3. Click **Import**

> **Note:** The ToolBox workflow bundles all individual tools (scratchpad, Webex notifications, change approval, terminal commands, and RADKIT tools) as subworkflows. You do not need to import them separately.

#### 1.6.4 Import AI Agent

1. Click **Actions** -> **Import Workflow** -> **Git** tab
2. Select:
   - **Repository:** `LTRAI-1487 - AI Agent`
   - **Workflow:** `AIAgent`
   - **Version:** Latest
3. Click **Import**
4. When prompted for **OPENAI_API_KEY**, enter the API key found in the dCloud file
   - **Ask your instructor if you cannot locate this key**

#### 1.6.5 Validate All Workflows

After importing all workflows, validate that they are configured correctly:

1. Go to **Automation** -> **Workspace**
2. For each imported workflow:
   - Click on the workflow name to open it
   - Click **Validate** in the upper right corner
   - Ensure there are no validation errors
3. If you see any errors, check that all required credentials were entered correctly

You should have imported a total of **5 workflows**:
- 1 from AI repository (OpenAIChatCompletion)
- 2 from MCP repository (MCPListTools, MCPRunTool)
- 2 from AI Agent repository (ToolBox + AIAgent)

#### 1.6.6 Verify OpenAI Endpoint Configuration

1. Go to **Automation** -> **Targets**
2. Click on **OPENAI_ENDPOINT**
3. Verify the following settings:
   - **Host:** `ciscolive-llm.com`
   - **Port:** `443`
   - **Path:** (leave blank)
4. If any settings are incorrect, update them and click **Save**

### 1.7 Test the AI Agent

Now let's verify the AI Agent workflow runs correctly before connecting it to your event trigger.

1. Go to **Automation** -> **Workspace**
2. Click on **AIAgent** to open the workflow
3. Click **Run** in the upper right corner
4. When prompted, fill out the input variables:
   - **i_agent_task:** `Go to r1, get the current time and interfaces which are up. Output these results exactly to webex and include a short summary.`
5. Click **Run** to execute the workflow
6. Monitor the workflow execution and verify it completes without errors
7. Check your Webex space to confirm the agent sent the results

> **Success Criteria:** The workflow should complete successfully, and you should receive a Webex message containing the device time, interface status, and a summary from the AI Agent.

> **Troubleshooting:** If the workflow fails:
> - Verify the OPENAI_API_KEY is set correctly
> - Check that the OPENAI_ENDPOINT target is configured properly
> - Ensure your Webex access token is valid

### 1.8 Configure the Webex Notification Tool (Optional)

The Webex notification capability is embedded within the ToolBox workflow as a subworkflow. If you need to customize the Webex room or dashboard URL, follow these steps:

#### 1.8.1 Configure Workflow Variables

1. Go to **Automation** -> **Workspace**
2. Click on **ToolBox** to open the workflow
3. In the workflow canvas, locate and double-click on the **ToolSendWebexNotification** subworkflow
4. On the right side panel, expand **Variables**
5. Update the **Local Variables** if needed:
   - `l_meraki_dashboard_url` - Your Meraki Dashboard URL
   - `l_room_name` - The Webex room/space name for notifications

> **Tip:** The room name should match an existing Webex space where you want to receive AI Agent notifications.