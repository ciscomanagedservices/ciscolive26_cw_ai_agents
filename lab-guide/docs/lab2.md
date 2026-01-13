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
2. Browse to **Automation> Targets> Remote Targets** click **+ New Remote**.
3. Set the **Display name** to `<your_name>-remote` and click **Save**.
4. Back on the **Remote Targets** page, click the **...** under **Actions** and choose **Connect**.
5. Click **Generate Package** from the popup. This will generate and automatically download a file `remotePackage.zip`.
6. Copy the file over to the wf-remote server (198.18.1.204):
```sh
scp remotePackage.zip root@198.18.1.204:/root/
```
7. Run the python script passing in the zip package to initiate the remote server registration procedure:
```sh
./register_remote.py remotePackage.zip
```
8. Wait a few seconds, and then refresh the Workflow's Targets page. You should see your remote move into a `Connected` status.

> **Note:** The official process for registering a remote server differs from this a bit. Cisco Workflows currently only supports remote servers running on virtual appliances where you can pass the initialization/registration text into an OVF template. Since dCloud doesn't support OVF templates, we feed the remotePackage into a python script that runs the same cloud init script that the OVF template would have triggered. For the full documentation on deploying a remote server, see the official [Cisco Workflows documentation](https://documentation.meraki.com/Platform_Management/Workflows/Targets/Automation_Remote/Remote_Setup_and_Deployment).

## Step 2: Configuring remote targets

### 2.1 Configuring R3 as a target
1. In **Automation> Targets** go to **+ New target** and set:
    - **Target type:** `Terminal endpoint`
    - **Display name:** `<your_name>-R3`
    - **Target type:** `Terminal endpoint`
    - **Remote Keys:** `<your_name>-remote` #This specifies that this device should use the remote server to connect
    - **Protocol:** `SSH`
    - **Host/IP Address:** `198.18.1.103`    
    - **Port:** `22`    
    - **Prompt:** `#`
2. Under **Default Account Keys**, click the down arrow and say **Add new** and specify:
    - **Account Key Type**: `Terminal password-based credentials`
    - **Display Name**: `<your_name>-R3-creds`
    - **User name:** `cisco`
    - **Password:** `cisco`    
3. Ensure that the **status** of the devices shows as `Valid` which is ensuring a basic connection check to the device.

### 2.2 Create a Target group
Target groups contain the sets of devices that you can run the automation on. We want to create a group that would contain all possible devices that we'd run the automation on.

> Info:
> Target groups can only be associated at the workflow level, not at the per-activity level. The same target group needs to apply across all activities that need targets. So if we have a workflow with activities to multiple targets in the same workflow, they need to be in the same target group. There are two approaches here: a) Move the webex notification to a standalone workflow overriding the target to the webex URL, and call it with the **Workflows** activity; or b) Put both targets in a target group, and use the **override target condition** function to define a conditional that picks the appropriate target(s) from the aggregate target group list. This is overly complicated, so let's take Approach A.

1. Go to **Automation> Targets> + New target group** and name it `<your_name>-routers`.
2. Click **+ Add target type** and choose the **target type** of `Terminal Endpoint`.
3. You could either implicitly add all targets you'd potentially run the automation on here, specify a matching condition, or you could enable the **Include all targets of this type** if all terminal endpoints should get this workflow treatment. Since we are potentially dealing with other lab pods in the same tenant, let's just add our one device matching `<your_name>-R3` into the target group. You could add your other pod routers in this group in the future, if you want.

### 2.3 Convert the notification atomic to a standalone workflow
1. Go back to the workflow list, and duplicate your workflow under the **...> Duplicate** section. Call the new workflow `<your_name>-notify2`
2. Under workflow **variables**, click **+ Add variable** and add a String variable named `message_body`, with **Scope** of input and enable **required for workflow to run**. Set the default value to `-1` just so you know if it doesn't get set properly.
3. Change the **Markdown Message** field to pull the workflow input variable `message_body`.
4. Ensure the target is set to **override workflow target** and set to `<your_name>-webex`

### 2.4 Parsing webhook content in workflow for target device
1. Now lets create a new workflow called `<your_name>-unshut-int`
2. First we need to parse out the device that generated the event, which is in the webhook JSON payload.
3. Find the **JSONPath Query** activity and drag it below **Start**. 
4. In the **Source JSON to Query** click the variable icon and select **Rule> Webhook Rule> Output> Request Body**.
5. We need to parse the JSON from the webhook for the variable `dvc`, so we will use **JSONPath Query** of `$.result.dvc` to extract the value (device IP) from that JSON path.
6. Under **Property Name** set it to `target_device`, which will define the variable the extracted IP will be stored in for later reference. Use property type of `String`.
7. Finally a good practice is to name the display name something succinct but describing the purpose of the block, so let's call it `get_device_ip`.

### 2.5 Defining commands to send to the device

1. In **Activities** drag the **Terminal> Execute Terminal Commands** activity below the JSON activity.
2. Set the **Display Name** to something like `unshut interface`.
3. In the **Terminal> Input Commands** section add commands to unshut the interface:
```cisco
conf t
int lo0
no sh
send log "Cisco Workflows has automated unshutting an interface." 
```
5. Try to set the Target to use our target group.
6. See how can't set the target group in the activity? You only can override a single target or the target group criteria? Workflows expects that we have the target group defined at the workflow level.
7. Click off the activity to get the main workflow parameters and now set the workflow **Target** to `Execute on this target group` and select your `<your_name>-routers` group.
8. Now we need to add a filtering condition to our target group which selects the actual device(s) you want to use, but at the workflow level we haven't yet defined the actual device IP, since we need to parse the JSON step after the workflow runs. So we need to set some dummy target group criteria to pass syntax check.
9. Choose the **target type** of `Terminal Endpoint` and add a condition where:
    - **Property**: (variable) `Terminal Endpoint> Input> Host/IPAddress`
    - **Comparison**: `Equals`    
    - **Value**: `-2`
10. The above condition's intent is to never be true. We will instead override this criteria in the **Execute Terminal Command** block once we have the appropriate device IP from the webhook parsing.
11. Now go back into the command activity block, and choose **Override target group condition** and set the condition to:
    - **Property**: (variable) `Terminal Endpoint> Input> Host/IPAddress`
    - **Comparison**: `Equals`    
    - **Value**: `Activities> JSONPath Query> JSONPath Queries> target_device`

### 2.6 Adding notification

1. Now we will go to the workflow tab on the left sidebar, and get our workflow `<your_name>-notify2` and drag it below the command activity.
2. Click the notify2 workflow instance, and in the `message_body` input set it to the response from the terminal commands (`Activities> Execute Terminal Commands> Response body`). This will send the command responses to the notification. You could add additional text or variables in here, if you desire, for more detailed notification.
3. Click **Validate** and ensure the workflow passes syntax checks.

### 2.7 Changing the workflow trigger

1. Go to the trigger you defined for the original notification workflow and change the triggered workflow from that to your new `*-shut-int` workflow.

## Step 3: Validation

1. Go to R3, ensure the loopback0 interface is in an up state. If not, bring it up and then `clear log`.
2. Shut the loopback0 interface down with `shut`
3. Wait about 90 seconds, and see if your new workflow runs in **More Actions> View runs**.

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