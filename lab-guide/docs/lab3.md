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

### 1.7 Test Individual Tools

Before testing the full AI Agent, let's verify that the individual tools work correctly.

#### 1.7.1 Test RADKit Exec Command Tool

1. Go to **Automation** -> **Workspace**
2. Click on **Tool - RADKIT Exec Command** to open the workflow
3. Click **Run** in the upper right corner
4. When prompted, fill out the input variables:
   - **i_device_name:** `r1`
   - **i_commands:** `show version`
5. Click **Run** to execute the workflow
6. Verify the workflow completes successfully and returns the device output

> **Success Criteria:** The workflow should complete without errors and display the `show version` output from device r1.

#### 1.7.2 Test Webex Notification Tool

1. Go to **Automation** -> **Workspace**
2. Click on **Tool - Send Webex Notification** to open the workflow
3. On the right side panel, expand **Variables**
4. Update the local variable `l_room_name` to the name of your test Webex space that has the Webex bot
5. Click **Run** in the upper right corner
6. When prompted, fill out the input variables:
   - **i_instance_id:** `test`
   - **i_message:** `Hello from the AI Agent lab! This is a test notification.`
7. Click **Run** to execute the workflow
8. Check your Webex space to verify you received the message

> **Success Criteria:** You should see your test message appear in the configured Webex room.

### 1.8 Test the AI Agent

Now let's verify the full AI Agent workflow runs correctly.

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
> - Re-run the individual tool tests (1.7.1 and 1.7.2) to isolate the issue

---

## Step 2: Create AI Agent Workflow for Event Remediation

Now that you have the AI Agent working, let's connect it to respond to the same network event from Lab 2. Instead of hardcoded commands, the AI Agent will cognitively analyze the event and determine the appropriate remediation.

### 2.1 Duplicate the Lab 2 Workflow

We'll start by duplicating your Lab 2 workflow and modifying it to use the AI Agent.

1. Go to **Automation** → **Workspace**
2. Find your workflow `<your_name>-unshut-int` from Lab 2
3. Click the **...** menu on the workflow and select **Duplicate**

### 2.2 Configure the New Workflow

1. Click on the duplicated workflow `Copy(1) <your_name>-unshut-int` to open it
2. In the **General** tab, rename the workflow to `<your_name>-ai-fix-shut-interface`
3. Delete the **Terminal** activity (the static remediation commands)
4. Delete the existing **sub workflow** activity

### 2.3 Add the AI Agent Activity

1. On the left side panel, click **Workflows**
2. Search for `AI Agent`
3. Drag the **AIAgent** workflow into the flow after the **JSON Path Query** activity

### 2.4 Configure the AI Agent Task

1. Click on the **AI Agent** block to select it
2. Expand the `i_agent_task` input variable
3. Configure it with the following text:

```
A network event was received for device
```

4. After "device ", add a **reference variable** pointing to the JSON Path Query output `target_device`
5. Continue the text:

```
:

raw event:

```

6. Add another **reference variable** pointing to the **Webhook Request Body**
7. Finally, add this instruction at the end:

```

You MUST proceed with investigation. If any change is required to resolve alert, you MUST call tool to request change approval.
```

> **Note:** We're keeping it simple - giving the agent minimal parsing and letting it analyze the raw event. The final instruction ensures the agent requests your approval before making any changes.

### 2.5 Validate the Workflow

1. Click **Validate** in the upper right corner
2. Ensure there are no validation errors
3. If errors appear, verify the reference variables are correctly linked

### 2.6 Update the Trigger Rule

1. Go to **Automation** → **Rules**
2. Find your rule from Lab 1
3. **Enable** the action for the new `<your_name>-ai-fix-shut-interface` workflow
4. **Disable** the action for the prior `<your_name>-unshut-int` workflow

### 2.7 Test the AI Agent Response

1. SSH to R3 (198.18.1.103)
2. Execute the following commands to shut down the interface:
   ```
   conf t
   int lo0
   shut
   ```
3. Wait for the webhook to fire and observe the AI Agent workflow execution

### 2.8 Respond to Clarifying Questions (If Any)

The AI Agent may ask clarifying questions before proceeding - that's OK! It's just trying to make sure it's doing the right thing.

1. Check Webex for any **clarifying questions** from the agent
2. If the agent asks a question, click the **Cisco Workflow Run** link in the Webex message
3. In the Cisco Workflows UI, click **View Task**
4. Provide as much detail as possible to help the agent understand the situation:
   - Confirm the interface should be brought back up
   - Specify that this is a loopback interface on R3
   - Indicate that the interface was administratively shut down and needs to be restored

> **Tip:** The more context you provide, the better the agent can proceed with confidence and open a change request!

### 2.9 Approve the Change Request

Once the agent has enough information, it will request your approval before making changes:

1. Check Webex for a **change approval notification** from the agent
2. Click the **Cisco Workflow Run** link in the Webex message
3. In the Cisco Workflows UI, click **View Task**
4. Review the agent's proposed action and click **Approve** to allow the agent to bring the interface back up

> **Note:** The next lab uses a workflow with more detailed prompting for complex ThousandEyes troubleshooting scenarios.

### 2.10 Validation

1. Check R3: Run `show ip int brief` - loopback0 should be up after approval
2. Check Webex for the agent's completion notification
3. Review the workflow run to see the agent's reasoning chain

---

## Summary

You have successfully configured a cognitive AI Agent for network operations:

| Component | Status | Purpose |
|-----------|--------|---------|
| AI Agent Workflow | Imported | Orchestrates LLM-driven analysis and tool execution |
| OpenAI Integration | Configured | Provides cognitive reasoning capabilities |
| ToolBox | Imported | Gives agent access to device commands, notifications, and approvals |
| Event-Triggered Agent | Working | Responds to network events with intelligent remediation |

### Key Differences: Lab 2 vs Lab 3

| Aspect | Lab 2 (Static) | Lab 3 (Cognitive) |
|--------|----------------|-------------------|
| **Logic** | Hardcoded: `conf t`, `int lo0`, `no sh` | AI analyzes event and decides action |
| **Flexibility** | Only handles loopback0 | Can handle any interface/device |
| **Approval** | None - auto-executes | Human-in-the-loop via change approval |
| **Transparency** | Just runs commands | Agent explains reasoning in Webex |

In the next lab, you will integrate ThousandEyes for network performance monitoring and see the AI Agent troubleshoot more complex scenarios with enriched path data.

---

**Congratulations!** Once the AI Agent successfully brings loopback0 back up, Lab 3 is complete!