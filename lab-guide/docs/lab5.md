# Lab 5 - Extending the AI Agent with Custom Tools

## Prerequisites

Before starting this lab, ensure you have completed:

- **Lab 3** - AI Agent and ToolBox workflows must be imported and working
- **Lab 1** - Webex bot configured (for testing notifications)

---

## Overview

In this lab, you will learn how to extend the AI Agent's capabilities by creating a custom tool. You will build a weather retrieval tool that uses the public [wttr.in](https://github.com/chubin/wttr.in) API service.

By the end of this lab, you will have:

- Created an HTTP target for an external API
- Built a custom workflow that retrieves weather data
- Implemented retry logic for API reliability
- Integrated the new tool into the ToolBox workflow
- Added the tool specification to the AI Agent
- Tested the complete integration with a multi-step task

The following diagram illustrates the tool integration:

```txt
AI Agent -> [tool_call: get_weather] -> ToolBox -> Tool - Get Weather -> wttr.in API
                                                                              |
AI Agent <- [weather JSON response] <- ToolBox <-----------------------------+
```

> **Note:** The wttr.in API is a free public service that may occasionally experience outages. If you encounter issues, your instructor can provide an alternative approach using Tavily web search.

---

## Step 1: Create the HTTP Target

Before creating the workflow, we need to configure an HTTP target for the wttr.in weather API.

### 1.1 Navigate to Targets

1. In Cisco Workflows, go to <em class="button-click">Automation > Targets</em>
2. Click <em class="button-click">+ New target</em>
3. Select <em class="button-click">HTTP Endpoint</em> as the target type

### 1.2 Configure the HTTP Endpoint

1. Set <em class="lab-warning">Display name</em> to <em class="example-input">wttr.in weather api</em>
2. Set <em class="lab-warning">No account keys</em> to <em class="example-input">True</em>
3. Set <em class="lab-warning">Host/IP Address</em> to <em class="example-input">wttr.in</em>
4. Set <em class="lab-warning">Protocol</em> to <em class="example-input">HTTP</em>
5. Click <em class="button-click">Save</em>

> **Note:** We use HTTP (not HTTPS) for wttr.in as the service works reliably over HTTP.

---

## Step 2: Create the Weather Workflow

Now we will create the workflow that retrieves weather data for a given city.

### 2.1 Create a New Workflow

1. Go to <em class="button-click">Automation > Workspace</em>
2. Click <em class="button-click">+ Create</em>
3. Select <em class="button-click">Blank Custom Workflow</em> and click <em class="button-click">Continue</em>
4. Name the workflow <em class="example-input">Tool - Get Weather</em>

### 2.2 Configure Workflow Description

1. From the canvas screen, click the <em class="button-click">General</em> tab
2. Add a description: <em class="example-input">Takes in a City name and gets the weather, returns results in JSON</em>

### 2.3 Configure Variables

Expand the **Variables** tab and create two variables:

**Input Variable - i_city_name:**
1. Click <em class="button-click">+ Add variable</em>
2. Set <em class="lab-warning">Name</em> to <em class="example-input">i_city_name</em>
3. Set <em class="lab-warning">Type</em> to <em class="example-input">String</em>
4. Set <em class="lab-warning">Scope</em> to <em class="example-input">Input</em>
5. Set <em class="lab-warning">String type</em> to <em class="example-input">Text</em>
6. Add <em class="lab-warning">Description</em>: <em class="example-input">Name of city for weather retrieval</em>
7. Click <em class="button-click">Save</em>

**Output Variable - o_message_content:**
1. Click <em class="button-click">+ Add variable</em>
2. Set <em class="lab-warning">Name</em> to <em class="example-input">o_message_content</em>
3. Set <em class="lab-warning">Type</em> to <em class="example-input">String</em>
4. Set <em class="lab-warning">Scope</em> to <em class="example-input">Output</em>
5. Set <em class="lab-warning">String type</em> to <em class="example-input">JSON</em>
6. Add <em class="lab-warning">Description</em>: <em class="example-input">Weather results in JSON</em>
7. Click <em class="button-click">Save</em>

### 2.4 Add HTTP Request Activity

1. From the left pane, expand <em class="button-click">Activities > Web Service</em>
2. Drag the <em class="lab-warning">HTTP Request</em> activity to the canvas below <em class="lab-warning">Start</em>
3. Click on the HTTP Request block and configure:
   - <em class="lab-warning">Display Name</em>: <em class="example-input">get weather from wttr.in</em>
   - <em class="lab-warning">Relative URL</em>: Click the text field, then click the variable icon and select <em class="example-input">i_city_name</em>. Add <em class="example-input">?format=j1</em> after the variable so the full URL looks like: <em class="example-input">/{i_city_name}?format=j1</em>
   - <em class="lab-warning">Activity Timeout</em>: <em class="example-input">60</em>
   - <em class="lab-warning">Target</em>: Select <em class="button-click">Override workflow target</em> and choose <em class="example-input">wttr.in weather api</em>

### 2.5 Add Set Variables Activity

1. From the left pane, drag a <em class="lab-warning">Set Variables</em> activity below the HTTP Request
2. Click on the Set Variables block
3. Add a variable assignment:
   - <em class="lab-warning">Variable to update</em>: <em class="example-input">o_message_content</em>
   - <em class="lab-warning">Value</em>: Click the variable icon and select <em class="button-click">Activities > HTTP Request > Response Body</em>

### 2.6 Test the Workflow

1. Click <em class="button-click">Validate</em> in the upper right corner
2. Click <em class="button-click">Run</em>
3. When prompted, enter <em class="example-input">amsterdam</em> for <em class="lab-warning">i_city_name</em>
4. Click <em class="button-click">Run</em> to execute
5. Verify the workflow completes successfully
6. Check that <em class="lab-warning">o_message_content</em> contains a detailed JSON blob with weather data for Amsterdam

> **Tip:** If the test fails, verify your HTTP target configuration and ensure wttr.in is accessible from the internet.

---

## Step 3: Add Retry Logic

The wttr.in API is free and not always reliable. Let's add retry logic to handle temporary failures.

### 3.1 Add Condition Block

1. Click <em class="button-click">Modify</em> to edit the workflow
2. From the left pane, drag a <em class="lab-warning">Condition Block</em> below the HTTP Request activity
3. You now have two condition branches to configure

### 3.2 Configure Success Path (HTTP 200)

1. Click on the left condition branch
2. Set <em class="lab-warning">Display Name</em> to <em class="example-input">http code == 200</em>
3. Configure the condition:
   - <em class="lab-warning">Property</em>: Select <em class="button-click">Activities > HTTP Request > Status Code</em>
   - <em class="lab-warning">Comparison</em>: <em class="example-input">Equals</em>
   - <em class="lab-warning">Value</em>: <em class="example-input">200</em>

### 3.3 Configure Retry Path (HTTP != 200)

1. Click on the right condition branch
2. Set <em class="lab-warning">Display Name</em> to <em class="example-input">http code != 200</em>
3. Configure the condition:
   - <em class="lab-warning">Property</em>: Select <em class="button-click">Activities > HTTP Request > Status Code</em>
   - <em class="lab-warning">Comparison</em>: <em class="example-input">Not equals</em>
   - <em class="lab-warning">Value</em>: <em class="example-input">200</em>

### 3.4 Add Sleep Block for Retry

1. From the left pane, drag a <em class="lab-warning">Sleep</em> activity as the first activity in the <em class="example-input">http code != 200</em> branch
2. Set the sleep duration to <em class="example-input">10</em> seconds

### 3.5 Duplicate Activities for Each Path

**For the Success Path (== 200):**
1. Move or add a <em class="lab-warning">Set Variables</em> activity in the success branch
2. Configure it to set <em class="lab-warning">o_message_content</em> from the original HTTP Request's Response Body

**For the Retry Path (!= 200):**
1. Duplicate the <em class="lab-warning">HTTP Request</em> block and add it after the Sleep activity
2. Duplicate the <em class="lab-warning">Set Variables</em> block and add it after the retry HTTP Request
3. Ensure the Set Variables block references the <em class="lab-warning">retry HTTP Request's Response Body</em> (not the original)

> **Important:** Make sure each Set Variables block references the correct HTTP Request activity above it in the flow.

### 3.6 Validate and Test

1. Click <em class="button-click">Validate</em> to ensure no errors
2. Click <em class="button-click">Run</em> and test with <em class="example-input">amsterdam</em> again
3. Verify the workflow still completes successfully

---

## Step 4: Integrate Tool into ToolBox

Now we need to add our new tool to the ToolBox workflow so the AI Agent can use it.

### 4.1 Open the ToolBox Workflow

1. Go to <em class="button-click">Automation > Workspace</em>
2. Click on the <em class="button-click">ToolBox</em> workflow to open it
3. Click <em class="button-click">Modify</em> to edit

### 4.2 Duplicate an Existing Tool Block

1. Find the <em class="lab-warning">Tool - Send Webex Notification</em> condition block
2. Right-click and select <em class="button-click">Duplicate</em> (or use the duplicate option in the menu)
3. Position the duplicated block in the workflow

### 4.3 Configure the Tool Condition

1. Click on the duplicated condition block
2. Change the <em class="lab-warning">Display Name</em> to <em class="example-input">Get Weather</em>
3. Modify the condition so <em class="lab-warning">i_tool_call_name</em> equals <em class="example-input">get_weather</em>

> **Note:** The value <em class="example-input">get_weather</em> will be the tool name as seen by the LLM.

### 4.4 Update the JSONPath Query

1. Click on the <em class="lab-warning">JSONPath Query</em> block within your new tool section
2. Change the property name from <em class="lab-warning">i_instance_id</em> to <em class="example-input">i_city_name</em>
3. Update the JSONPath expression to extract city name: <em class="example-input">$.i_city_name</em>
4. Delete the <em class="lab-warning">$.i_message</em> query as it's not needed for this tool

### 4.5 Replace the Subworkflow

1. Delete the <em class="lab-warning">Tool - Send Webex Notification</em> subworkflow block
2. From the left pane under <em class="button-click">Workflows</em>, search for <em class="example-input">Tool - Get Weather</em>
3. Drag it into the workflow in place of the deleted block

### 4.6 Wire Up Variables

1. Click on the <em class="lab-warning">Tool - Get Weather</em> block
2. Set the input <em class="lab-warning">city_name</em> to reference the JSONPath Query output <em class="example-input">i_city_name</em>
3. Click on the <em class="lab-warning">Set o_message_content</em> block below
4. Update the reference value to use the output variable from <em class="lab-warning">Tool - Get Weather</em>

### 4.7 Test the ToolBox

1. Click <em class="button-click">Validate</em>
2. Click <em class="button-click">Run</em> to test
3. Set the input variables:
   - <em class="lab-warning">i_tool_call_name</em>: <em class="example-input">get_weather</em>
   - <em class="lab-warning">i_tool_call_arguments</em>:
   ```json
   {"i_city_name": "Amsterdam"}
   ```
4. Verify the workflow completes and returns weather data

---

## Step 5: Add Tool to AI Agent Specification

The AI Agent needs to know about the new tool through its function specification.

### 5.1 Open the AI Agent Workflow

1. Go to <em class="button-click">Automation > Workspace</em>
2. Click on the <em class="button-click">AIAgent</em> workflow
3. Click <em class="button-click">Modify</em> to edit

### 5.2 Edit the Tools Variable

1. In the right panel, expand <em class="lab-warning">Variables</em>
2. Find and click on <em class="lab-warning">i_tools_json</em>
3. Edit the JSON array to add the new tool specification

### 5.3 Add the Function Specification

Add the following JSON object after line 1 (after the opening `[`):

```json
  {
    "type": "function",
    "function": {
      "name": "get_weather",
      "description": "Takes in a City name and gets the weather",
      "parameters": {
        "type": "object",
        "properties": {
          "i_city_name": {
            "type": "string",
            "description": "Name of city for weather retrieval"
          }
        }
      }
    }
  },
```

> **Tip:** For future tools, you can use the helper script in the repository to generate the OpenAI function specification from a workflow JSON:
> ```bash
> cat workflow.json | python3 scripts/tools/convert_toolbox_to_openai_tools.py --stdin --function-name get_weather
> ```

### 5.4 Validate JSON Syntax

1. Copy the entire <em class="lab-warning">i_tools_json</em> content
2. Paste it into [JSONLint](https://jsonlint.com) to validate
3. Ignore any warnings about duplicate keys for "type" - this is expected
4. Fix any syntax errors if found

---

## Step 6: Test the Complete Integration

### 6.1 Validate All Workflows

1. Go to <em class="button-click">Automation > Workspace</em>
2. Open each of these workflows and click <em class="button-click">Validate</em>:
   - Tool - Get Weather
   - ToolBox
   - AIAgent

### 6.2 Run the AI Agent Test

1. Click on the <em class="button-click">AIAgent</em> workflow
2. Click <em class="button-click">Run</em>
3. Set <em class="lab-warning">i_agent_task</em> to:
   ```
   1. Find out the weather in Amsterdam
   2. Send me a webex notification about the weather
   ```
4. Click <em class="button-click">Run</em> to execute

### 6.3 Verify Results

1. Monitor the workflow execution
2. Check your Webex space for a notification
3. You should receive a message containing weather information for Amsterdam

> **Troubleshooting:** If the workflow fails:
> - Verify the tool name <em class="example-input">get_weather</em> matches in both ToolBox and i_tools_json
> - Check that the JSONPath query correctly extracts <em class="lab-warning">i_city_name</em>
> - Ensure the HTTP target is properly configured
> - Review the workflow run details for specific error messages

---

## Summary

You have successfully extended the AI Agent with a custom tool:

| Component | Status | Purpose |
|-----------|--------|---------|
| HTTP Target | Created | Provides endpoint for wttr.in API |
| Tool - Get Weather | Created | Workflow that retrieves weather data |
| Retry Logic | Implemented | Handles API failures gracefully |
| ToolBox Integration | Complete | Routes get_weather calls to the workflow |
| AI Agent Spec | Updated | LLM can now invoke the weather tool |

### Key Takeaways

- Custom tools follow a consistent pattern: HTTP target, workflow, ToolBox integration, and function spec
- The ToolBox acts as a router, directing tool calls to the appropriate sub-workflows
- The OpenAI function specification tells the LLM what tools are available and how to call them
- Retry logic improves reliability when working with external APIs

### Next Steps

Consider extending your AI Agent with additional tools:
- Integration with your ITSM system (ServiceNow, Jira)
- Database lookups for configuration management
- Additional monitoring integrations (AppDynamics, Datadog)

> **Note:** As Cisco Workflows API becomes more open, tool creation and integration may become more streamlined in the future.
