# Lab 2 - Using Cisco Workflows for automated response

## Overview

In this lab, you will build on the event handling and workflow created in Lab 1, by setting up a remote server for Cisco Workflows to talk to your infrastructure through. You will define a rule-based remediation workflow, allowing for autonomous closed-loop infrastructure operations.

By the end of this lab, you will:

- Be able to have Cisco Workflows talk to devices in your infrastructure.
- Configure static / rule-based workflows where you can automate defined response and remediation.

This will show one way to have automated response, before we bring in cognitive agentic response.

The following diagram illustrates the event flow we are building:

```txt
device -> [syslog] -> splunk -> [webhook] -> Cisco Workflows -> [commands] -> Workflow's Remote Server -> device
```

---

## Step 1: Registering a remote server to Workflows

1. Go to [meraki.cisco.com](https://meraki.cisco.com)
2. Browse to <em class="button-click">Automation > Targets > Remote Targets</em> click <em class="button-click">+ New Remote</em>.
3. Set the <em class="lab-warning">Display name</em> to <em class="example-input">&lt;your_name&gt;-remote</em> and click <em class="button-click">Save</em>.
4. Back on the <em class="lab-warning">Remote Targets</em> page, click the <em class="button-click">...</em> under <em class="lab-warning">Actions</em> and choose <em class="button-click">Connect</em>.
5. Click <em class="button-click">Generate Package</em> from the popup. This will generate and automatically download a file <em class="example-input">remotePackage.zip</em>.
6. Copy the file over to the wf-remote server (<em class="example-input">198.18.1.204</em>):
```sh
scp remotePackage.zip root@198.18.1.204:/root/
```
7. SSH to the wf-remote server and clone the lab repository:
```sh
ssh root@198.18.1.204
git clone https://github.com/ciscomanagedservices/ciscolive26_cw_ai_agents.git
```
8. Run the python script passing in the zip package to initiate the remote server registration procedure:
```sh
cd ciscolive26_cw_ai_agents/scripts/remote_server
./remote_register.py /root/remotePackage.zip
```
9. Wait a few seconds, and then refresh the Workflow's Targets page. You should see your remote move into a `Connected` status.

> **Note:** The official process for registering a remote server differs from this a bit. Cisco Workflows currently only supports remote servers running on virtual appliances where you can pass the initialization/registration text into an OVF template. Since dCloud doesn't support OVF templates, we feed the remotePackage into a python script that runs the same cloud init script that the OVF template would have triggered. For the full documentation on deploying a remote server, see the official [Cisco Workflows documentation](https://documentation.meraki.com/Platform_Management/Workflows/Targets/Automation_Remote/Remote_Setup_and_Deployment).

## Step 2: Configuring remote targets

### 2.1 Configuring R3 as a target
1. In <em class="button-click">Automation > Targets</em> go to <em class="button-click">+ New target</em> and set:
    - <em class="lab-warning">Target type:</em> <em class="example-input">Terminal endpoint</em>
    - <em class="lab-warning">Display name:</em> <em class="example-input">&lt;your_name&gt;-R3</em>
    - <em class="lab-warning">Remote Keys:</em> <em class="example-input">&lt;your_name&gt;-remote</em> #This specifies that this device should use the remote server to connect
    - <em class="lab-warning">Protocol:</em> <em class="example-input">SSH</em>
    - <em class="lab-warning">Host/IP Address:</em> <em class="example-input">198.18.1.103</em>
    - <em class="lab-warning">Port:</em> <em class="example-input">22</em>
    - <em class="lab-warning">Prompt:</em> <em class="example-input">#</em>
2. Under <em class="lab-warning">Default Account Keys</em>, click the down arrow and say <em class="button-click">Add new</em> and specify:
    - <em class="lab-warning">Account Key Type</em>: <em class="example-input">Terminal password-based credentials</em>
    - <em class="lab-warning">Display Name</em>: <em class="example-input">&lt;your_name&gt;-R3-creds</em>
    - <em class="lab-warning">User name:</em> <em class="example-input">cisco</em>
    - <em class="lab-warning">Password:</em> <em class="example-input">cisco</em>
3. Ensure that the <em class="lab-warning">status</em> of the devices shows as <em class="example-input">Valid</em> which is ensuring a basic connection check to the device.

### 2.2 Create a Target group
Target groups contain the sets of devices that you can run the automation on. We want to create a group that would contain all possible devices that we'd run the automation on.

> Info:
> Target groups can only be associated at the workflow level, not at the per-activity level. The same target group needs to apply across all activities that need targets. So if we have a workflow with activities to multiple targets in the same workflow, they need to be in the same target group. There are two approaches here: a) Move the webex notification to a standalone workflow overriding the target to the webex URL, and call it with the **Workflows** activity; or b) Put both targets in a target group, and use the **override target condition** function to define a conditional that picks the appropriate target(s) from the aggregate target group list. This is overly complicated, so let's take Approach A.

1. Go to <em class="button-click">Automation > Targets > + New target group</em> and name it <em class="example-input">&lt;your_name&gt;-routers</em>.
2. Click <em class="button-click">+ Add target type</em> and choose the <em class="lab-warning">target type</em> of <em class="example-input">Terminal Endpoint</em>.
3. You could either implicitly add all targets you'd potentially run the automation on here, specify a matching condition, or you could enable the <em class="lab-warning">Include all targets of this type</em> if all terminal endpoints should get this workflow treatment. Since we are potentially dealing with other lab pods in the same tenant, let's just add our one device matching <em class="example-input">&lt;your_name&gt;-R3</em> into the target group. You could add your other pod routers in this group in the future, if you want.

### 2.3 Convert the notification atomic to a standalone workflow
1. Go back to the workflow list, and duplicate your workflow under the <em class="button-click">... > Duplicate</em> section. Call the new workflow <em class="example-input">&lt;your_name&gt;-notify2</em>
2. Under workflow <em class="lab-warning">variables</em>, click <em class="button-click">+ Add variable</em> and add a String variable named <em class="example-input">message_body</em>, with <em class="lab-warning">Scope</em> of <em class="example-input">input</em> and enable <em class="lab-warning">required for workflow to run</em>. Set the default value to <em class="example-input">-1</em> just so you know if it doesn't get set properly.
3. Change the <em class="lab-warning">Markdown Message</em> field to pull the workflow input variable <em class="example-input">message_body</em>.
4. Ensure the target is set to <em class="button-click">override workflow target</em> and set to <em class="example-input">&lt;your_name&gt;-webex</em>

### 2.4 Parsing webhook content in workflow for target device
1. Now lets create a new workflow called <em class="example-input">&lt;your_name&gt;-unshut-int</em>
2. First we need to parse out the device that generated the event, which is in the webhook JSON payload.
3. Find the <em class="lab-warning">JSONPath Query</em> activity and drag it below <em class="lab-warning">Start</em>.
4. In the <em class="lab-warning">Source JSON to Query</em> click the variable icon and select <em class="button-click">Rule > Webhook Rule > Output > Request Body</em>.
5. We need to parse the JSON from the webhook for the variable <em class="example-input">dvc</em>, so we will use <em class="lab-warning">JSONPath Query</em> of <em class="example-input">$.result.dvc</em> to extract the value (device IP) from that JSON path.
6. Under <em class="lab-warning">Property Name</em> set it to <em class="example-input">target_device</em>, which will define the variable the extracted IP will be stored in for later reference. Use property type of <em class="example-input">String</em>.
7. Finally a good practice is to name the display name something succinct but describing the purpose of the block, so let's call it <em class="example-input">get_device_ip</em>.

### 2.5 Defining commands to send to the device

1. In <em class="lab-warning">Activities</em> drag the <em class="button-click">Terminal > Execute Terminal Commands</em> activity below the JSON activity.
2. Set the <em class="lab-warning">Display Name</em> to something like <em class="example-input">unshut interface</em>.
3. In the <em class="lab-warning">Terminal > Input Commands</em> section add commands to unshut the interface:
```cisco
conf t
int lo0
no sh
send log "Cisco Workflows has automated unshutting an interface." 
```
5. Try to set the Target to use our target group.
6. See how can't set the target group in the activity? You only can override a single target or the target group criteria? Workflows expects that we have the target group defined at the workflow level.
7. Click off the activity to get the main workflow parameters and now set the workflow <em class="lab-warning">Target</em> to <em class="example-input">Execute on this target group</em> and select your <em class="example-input">&lt;your_name&gt;-routers</em> group.
8. Now we need to add a filtering condition to our target group which selects the actual device(s) you want to use, but at the workflow level we haven't yet defined the actual device IP, since we need to parse the JSON step after the workflow runs. So we need to set some dummy target group criteria to pass syntax check.
9. Choose the <em class="lab-warning">target type</em> of <em class="example-input">Terminal Endpoint</em> and add a condition where:
    - <em class="lab-warning">Property</em>: (variable) <em class="button-click">Terminal Endpoint > Input > Host/IPAddress</em>
    - <em class="lab-warning">Comparison</em>: <em class="example-input">Equals</em>
    - <em class="lab-warning">Value</em>: <em class="example-input">-2</em>
10. The above condition's intent is to never be true. We will instead override this criteria in the <em class="lab-warning">Execute Terminal Command</em> block once we have the appropriate device IP from the webhook parsing.
11. Now go back into the command activity block, and choose <em class="button-click">Override target group condition</em> and set the condition to:
    - <em class="lab-warning">Property</em>: (variable) <em class="button-click">Terminal Endpoint > Input > Host/IPAddress</em>
    - <em class="lab-warning">Comparison</em>: <em class="example-input">Equals</em>
    - <em class="lab-warning">Value</em>: <em class="button-click">Activities > JSONPath Query > JSONPath Queries > target_device</em>

### 2.6 Adding notification

1. Now we will go to the workflow tab on the left sidebar, and get our workflow <em class="example-input">&lt;your_name&gt;-notify2</em> and drag it below the command activity.
2. Click the notify2 workflow instance, and in the <em class="lab-warning">message_body</em> input set it to the response from the terminal commands (<em class="button-click">Activities > Execute Terminal Commands > Response body</em>). This will send the command responses to the notification. You could add additional text or variables in here, if you desire, for more detailed notification.
3. Click <em class="button-click">Validate</em> and ensure the workflow passes syntax checks.

### 2.7 Changing the workflow trigger

1. Go to the trigger you defined for the original notification workflow and change the triggered workflow from that to your new <em class="example-input">*-unshut-int</em> workflow.

## Step 3: Validation

1. Go to R3, ensure the <em class="lab-warning">loopback0</em> interface is in an up state. If not, bring it up and then <em class="example-input">clear log</em>.
2. Shut the loopback0 interface down with <em class="example-input">shut</em>
3. Wait about 90 seconds, and see if your new workflow runs in <em class="button-click">More Actions > View runs</em>.

## Step 4: Troubleshooting

1. The same steps for isolating the problem that we used in Lab1 apply here.
2. If you see errors in your workflow, inspect the JSON errors to determine what the issue is.

---

## Summary

You have successfully configured the foundational infrastructure for agentic network operations:

| Component | Status | Purpose |
|-----------|--------|---------|
| Remote Server | Registered | Allows for sending terminal commands to devices |
| Cisco Workflows | Automated response | Now performing automated actions on devices |
| Target groups | Educational | Learned application for target groups for automating across your estate |

In the next lab, you will configure Cisco Workflows to have cognitive agentic intelligence, where it determines the next steps instead of you defining what commands to run. We will also leverage Cisco IQ's remote device connectivity (formerly known as CX RADKit) to simplify managing devices across the estate.