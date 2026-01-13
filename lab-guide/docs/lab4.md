# Lab 4 - Agentic response with ThousandEyes and dynamic network path data

## Recap

So far you have:
* Integrated a network topology's events into Cisco Workflows
* Configured deterministic automated response in Workflows
* Configured agentic operational response into Workflows
* Integrated inventory and remote access with RADKit

## Overview

In this lab, you will build on the agentic response, but instead trigger troubleshooting off an assurance event from ThousandEyes for digital user experience degrading.

By the end of this lab, you will:

- Have ThousandEyes integrated into Cisco Workflows
- Enrich the event data with network path data from ThousandEyes path info
- Observe how effective troubleshooting is with *just* an event from ThousandEyes and device access

The following diagram illustrates the event flow we are building:

```txt
ThousandEyes agent -> [webhook] -> Cisco Workflows -> [MCP] -> RadKit -> device(s)
```

---

## Step 1: Setting up ThousandEyes Agent

### 1.1 Register the agent appliance

1. Go to https://198.18.1.202 and login with `admin / welcome`.
2. Set the new password and click **change password**. `Cisco123!` will work for the password policy.
3. Add account `pl4okteoylmox9t60vi1ghz456ixeoa7` and click `continue`.
4. Click `Complete`. Don't worry about the Gateway not pingable and NTP server errors. They will resolve.
5. Change the **hostname** to `<your_name>-thousandeyes` and **Save Changes**

### 1.2 Validate registration

1. Login to https://www.thousandeyes.com and go to **Network & App Synthetics> Agent Settings**.
2. You should see your agent in the list, under the hostname field.
3. Notice how the agent name has a random ID suffix created during registration due to everyone participating in the lab having the same OS hostname. Let's rename this agent name as well for better identification. Click the agent and change **Agent Name** to be `<your_name>-thousandeyes` and **Save Changes**.

## Step 2: Configuring ThousandEyes Testing

### 2.1 Configure the HTTP Server test
1. Login to https://www.thousandeyes.com and go to **Network & App Synthetics> Test Settings> Add New Test> HTTP Server**.
2. Configure URL of https://cisco.webex.com
3. Run the test every `1 minute`
4. **Select Agents**. Select your Agent name `<your_name>-thousandeyes`. Make sure you change the **Default interface selection** to `eth1 198.18.13.202` so the test runs out the access network across R3-R2-R1 instead of across the mgmt network. Click **Close**.
5. Click **Deploy**.

### 2.2 Configure an alert for the test
1. **Manage> Alert Rules> Add New Alert Rule**
2. Set these parameters:
* **Alert Type: ** `Web> HTTP Server`
* **Alert Rule Name**: `Congestion Alert`
* **Tests**: `<Select your test name from 2.1>`
* **Agents**: `<Select your agent>`
3. Change **Alert Detection** to `Manual`

> [!TIP]
> Adaptive alerting is a neat feature, but it requires a day to run to build normality for the anomaly detection. We don't have that much time here, so even in a world of predictive AI, we're going with old-school manual thresholds.

4. Set to `Any conditions are met by the same 1 agent 2 of 2 times in a row`
5. Set the rules to:
* **Latency** >= 200ms
* **Jitter** >= 200ms
* **Packet Loss** >= 5%
* **Error** is present
6. Stay on this screen through the next step.

### 2.3 Configuring the webhook integration in Workflows

1. Now we need to create a new webhook for our ThousandEyes event. **Automation> Rules> Webhooks> + New webhook** 
2. Name it `<your_name>-te`
3. **Save** and then go back and view it to get the URL and save this to your local notepad for later reference.

### 2.4 Configuring the webhook integration in ThousandEyes

1. Click the **Notifications** tab below the alert name you specified.
2. Enable **Send emails** to your personal email, if desired. This is sometimes helpful to see quickly when alerts change state.
3. Under **Integrations** click **Manage integrations** and go to **Integrations 2.0**.
4. Choose **Custom Webhook**
5. Name the webhook `<your_name>-wh`.
6. Define the target as the Cisco Workflows webhook URL you created earlier in this lab.
7. No Auth Type is needed since the API key is in the URL.
8. Click **Save and assign operation**
9. Set **Operation Name** to `<your_name>-congestion-json` and choose the **Preset Configuration** of `Splunk`. We aren't sending to Splunk but the preset for Splunk is a nice simple JSON format that Cisco Workflows and our AI agent will nicely process. It should prepopulate the **Content-Type** header for `application/json` which we want.
10. Leave this browser tab open. We will run a test by clicking the **test** button after we configure our workflow to handle ThousandEyes.

### 2.5 Importing a workflow for ThousandEyes event handling
1. In Cisco Workflows, go to the Automation Workspace where the workflows are listed.
2. Add the git repo for ThousandEyes workflows like you did in Lab 3. `https://github.com/ciscomanagedservices/ciscolive26_cw_ai_agents/tree/main/workflows/ThousandEyes`
3. Click **Actions> Import Workflow> From Git** and import the `get_te_path_info` workflow first, and then `te_alert_webhook` workflow.


### 2.6 Configuring the trigger for the workflow

1. Now go back to Cisco Workflows and  **Automation> Rules> Automation rules> + New automation rule** and hook your new ThousandEyes webhook and workflow up.

## Step 3: Create congestion on the network to generate an incident

### 3.1 Create impairment
1. Let's create impairment on R2 in the middle of the router chain. `ssh cisco@198.18.1.102`
2. Run `event manager run CONGESTION_ON` which triggers an applet to apply interface policing and shaping on Gig1 and Gig2 to impair the access network.

### 3.2 Validating the troubleshooting run
1. It will take a few minutes for ThousandEyes to see the result, since we have a 2 minute alert. Any one have any good stories or jokes? If not, Steve is going to play music he likes which may not be to your favor.
2. If you signed up for an email alert, you should receive it soon. Otherwise, check the **workflow run** section in Cisco Workflows to validate that the workflow has started to run.
3. It should now be troubleshooting the network. This takes some time to analyze output and determine the action to take for remediation--roughly 20 minutes with current early 2026 models. To watch for progress as it troubleshoots you can click **...** on the `AI Agent` subworkflow in the webhook workflow run, and then click `Update I_messages variable` to watch for the latest updates in realtime. You will want to change the iteration in the main `Agent Iteration Loop` to the last or second to last iteration (sometimes the last iteration is still processing and won't have content).
4. Alternatively, you can just wait for Webex Teams summary messages at milestones.
5. Eventually you should see it request a task to be approved. Go to **Automation> User Tasks** to see if it is requesting a task approval. If it needs more info from you, it may also request something in **Prompts** but for this use case we don't expect it to need a prompt as it should have all the info it needs from ThousandEyes + RADKit to identify what it needs to solve the issue.
6. Once you see the change request, take a look at it. You should see a well curated explanation of the symptom, isolation to the root cause, and suggested fix if the change is approved. It even qualifies the risk of the change.
7. Click **Approve**. It will take a few more minutes, but then the policy should be removed and ThousandEyes alert should clear.
8. The agent may keep assessing. We often see that after the fix it analyzes like a Problem Manager would, to determine how to prevent this issue from ever occurring again. See if you see that and a second change request.

---

## Summary

That's it--great job!

You have successfully configured:

| Component | Status | Purpose |
|-----------|--------|---------|
| ThousandEyes | Connected | Detects network performance degradation and triggers alerts |
| Cisco Workflows | Automated response | Now performing automated actions on devices |
| RADKit | Integrated | Provides secure device access for troubleshooting |

And with that, you have seen event stimulus to drive agentic network troubleshooting, all the way through root cause resolution.

Now--imagine the power of it having the ThousandEyes alert, network path, and access to device level events/logs. What other types of your network issues do you think you can use Cisco workflows ambient agent to solve for you?

## Take home ideas

We encourage you to continue to test and enhance the power of agentic troubleshooting at home. Some other things to consider trying are:
* What tool would you build? Try to build another tool and integrate it into the AI agent. See the `scripts/tools/convert_toolbox_to_openai_tools.py`
* Integrating both device event/log data and observability event data from ThousandEyes, Splunk, AppDynamics, or other tools
* Integrate your knowledge base to augment and refine specific policies or processes
* Integrate with your enterprise ITSM change management, such as ServiceNow
