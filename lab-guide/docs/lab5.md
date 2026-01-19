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

1. In Cisco Workflows, go to **Automation > Targets**
2. Click **+ New target**
3. Select **HTTP Endpoint** as the target type

### 1.2 Configure the HTTP Endpoint

1. Set **Display name** to `wttr.in weather api`
2. Set **No account keys** to `True`
3. Set **Host/IP Address** to `wttr.in`
4. Set **Protocol** to `HTTP`
5. Click **Save**

> **Note:** We use HTTP (not HTTPS) for wttr.in as the service works reliably over HTTP.

---

## Step 2: Create the Weather Workflow

Now we will create the workflow that retrieves weather data for a given city.

### 2.1 Create a New Workflow

1. Go to **Automation > Workspace**
2. Click **+ Create**
3. Select **Blank Custom Workflow** and click **Continue**
4. Name the workflow `Tool - Get Weather`

### 2.2 Configure Workflow Description

1. From the canvas screen, click the **General** tab
2. Add a description: `Takes in a City name and gets the weather, returns results in JSON`

### 2.3 Configure Variables

Expand the **Variables** tab and create two variables:

**Input Variable - i_city_name:**
1. Click **+ Add variable**
2. Set **Name** to `i_city_name`
3. Set **Type** to `String`
4. Set **Scope** to `Input`
5. Set **String type** to `Text`
6. Add **Description**: `Name of city for weather retrieval`
7. Click **Save**

**Output Variable - o_message_content:**
1. Click **+ Add variable**
2. Set **Name** to `o_message_content`
3. Set **Type** to `String`
4. Set **Scope** to `Output`
5. Set **String type** to `JSON`
6. Add **Description**: `Weather results in JSON`
7. Click **Save**

### 2.4 Add HTTP Request Activity

1. From the left pane, expand **Activities > Web Service**
2. Drag the **HTTP Request** activity to the canvas below **Start**
3. Click on the HTTP Request block and configure:
   - **Display Name**: `get weather from wttr.in`
   - **Relative URL**: Click the text field, then click the variable icon and select `i_city_name`. Add `?format=j1` after the variable so the full URL looks like: `/{i_city_name}?format=j1`
   - **Activity Timeout**: `60`
   - **Target**: Select **Override workflow target** and choose `wttr.in weather api`

### 2.5 Add Set Variables Activity

1. From the left pane, drag a **Set Variables** activity below the HTTP Request
2. Click on the Set Variables block
3. Add a variable assignment:
   - **Variable to update**: `o_message_content`
   - **Value**: Click the variable icon and select **Activities > HTTP Request > Response Body**

### 2.6 Test the Workflow

1. Click **Validate** in the upper right corner
2. Click **Run**
3. When prompted, enter `amsterdam` for `i_city_name`
4. Click **Run** to execute
5. Verify the workflow completes successfully
6. Check that `o_message_content` contains a detailed JSON blob with weather data for Amsterdam

> **Tip:** If the test fails, verify your HTTP target configuration and ensure wttr.in is accessible from the internet.

---

## Step 3: Add Retry Logic

The wttr.in API is free and not always reliable. Let's add retry logic to handle temporary failures.

### 3.1 Add Condition Block

1. Click **Modify** to edit the workflow
2. From the left pane, drag a **Condition Block** below the HTTP Request activity
3. You now have two condition branches to configure

### 3.2 Configure Success Path (HTTP 200)

1. Click on the left condition branch
2. Set **Display Name** to `http code == 200`
3. Configure the condition:
   - **Property**: Select **Activities > HTTP Request > Status Code**
   - **Comparison**: `Equals`
   - **Value**: `200`

### 3.3 Configure Retry Path (HTTP != 200)

1. Click on the right condition branch
2. Set **Display Name** to `http code != 200`
3. Configure the condition:
   - **Property**: Select **Activities > HTTP Request > Status Code**
   - **Comparison**: `Not equals`
   - **Value**: `200`

### 3.4 Add Sleep Block for Retry

1. From the left pane, drag a **Sleep** activity as the first activity in the `http code != 200` branch
2. Set the sleep duration to `10` seconds

### 3.5 Duplicate Activities for Each Path

**For the Success Path (== 200):**
1. Move or add a **Set Variables** activity in the success branch
2. Configure it to set `o_message_content` from the original HTTP Request's Response Body

**For the Retry Path (!= 200):**
1. Duplicate the **HTTP Request** block and add it after the Sleep activity
2. Duplicate the **Set Variables** block and add it after the retry HTTP Request
3. Ensure the Set Variables block references the **retry HTTP Request's Response Body** (not the original)

> **Important:** Make sure each Set Variables block references the correct HTTP Request activity above it in the flow.

### 3.6 Validate and Test

1. Click **Validate** to ensure no errors
2. Click **Run** and test with `amsterdam` again
3. Verify the workflow still completes successfully

---

## Step 4: Integrate Tool into ToolBox

Now we need to add our new tool to the ToolBox workflow so the AI Agent can use it.

### 4.1 Open the ToolBox Workflow

1. Go to **Automation > Workspace**
2. Click on the **ToolBox** workflow to open it
3. Click **Modify** to edit

### 4.2 Duplicate an Existing Tool Block

1. Find the **Tool - Send Webex Notification** condition block
2. Right-click and select **Duplicate** (or use the duplicate option in the menu)
3. Position the duplicated block in the workflow

### 4.3 Configure the Tool Condition

1. Click on the duplicated condition block
2. Change the **Display Name** to `Get Weather`
3. Modify the condition so `i_tool_call_name` equals `get_weather`

> **Note:** The value `get_weather` will be the tool name as seen by the LLM.

### 4.4 Update the JSONPath Query

1. Click on the **JSONPath Query** block within your new tool section
2. Change the property name from `i_instance_id` to `i_city_name`
3. Update the JSONPath expression to extract city name: `$.i_city_name`
4. Delete the `$.i_message` query as it's not needed for this tool

### 4.5 Replace the Subworkflow

1. Delete the **Tool - Send Webex Notification** subworkflow block
2. From the left pane under **Workflows**, search for `Tool - Get Weather`
3. Drag it into the workflow in place of the deleted block

### 4.6 Wire Up Variables

1. Click on the **Tool - Get Weather** block
2. Set the input **city_name** to reference the JSONPath Query output `i_city_name`
3. Click on the **Set o_message_content** block below
4. Update the reference value to use the output variable from **Tool - Get Weather**

### 4.7 Test the ToolBox

1. Click **Validate**
2. Click **Run** to test
3. Set the input variables:
   - **i_tool_call_name**: `get_weather`
   - **i_tool_call_arguments**:
   ```json
   {"i_city_name": "Amsterdam"}
   ```
4. Verify the workflow completes and returns weather data

---

## Step 5: Add Tool to AI Agent Specification

The AI Agent needs to know about the new tool through its function specification.

### 5.1 Open the AI Agent Workflow

1. Go to **Automation > Workspace**
2. Click on the **AIAgent** workflow
3. Click **Modify** to edit

### 5.2 Edit the Tools Variable

1. In the right panel, expand **Variables**
2. Find and click on `i_tools_json`
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

1. Copy the entire `i_tools_json` content
2. Paste it into [JSONLint](https://jsonlint.com) to validate
3. Ignore any warnings about duplicate keys for "type" - this is expected
4. Fix any syntax errors if found

---

## Step 6: Test the Complete Integration

### 6.1 Validate All Workflows

1. Go to **Automation > Workspace**
2. Open each of these workflows and click **Validate**:
   - Tool - Get Weather
   - ToolBox
   - AIAgent

### 6.2 Run the AI Agent Test

1. Click on the **AIAgent** workflow
2. Click **Run**
3. Set `i_agent_task` to:
   ```
   1. Find out the weather in Amsterdam
   2. Send me a webex notification about the weather
   ```
4. Click **Run** to execute

### 6.3 Verify Results

1. Monitor the workflow execution
2. Check your Webex space for a notification
3. You should receive a message containing weather information for Amsterdam

> **Troubleshooting:** If the workflow fails:
> - Verify the tool name `get_weather` matches in both ToolBox and i_tools_json
> - Check that the JSONPath query correctly extracts `i_city_name`
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
