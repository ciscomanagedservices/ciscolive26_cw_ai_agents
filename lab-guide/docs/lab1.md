# Lab 1 - Setting up Network Topology

## Overview

In this lab, you will configure the foundational infrastructure required for agentic network operations.

By the end of this lab, you will have:

- Access to your dCloud lab environment
- Syslog forwarding from network device alerts to Splunk
- Splunk configured to trigger webhooks to Cisco Workflows on specific events
- Cisco Workflows configured with a workflow triggered by device events
- External tool integration with Cisco Workflows for Webex Teams notifications

This will serve as the detect & notify aspects of these labs.

The following diagram illustrates the event flow we are building:

```txt
device -> [syslog] -> splunk -> [webhook] -> Cisco Workflows -> [notification] -> Webex Teams
```

---

## Step 1: Access Your Lab Environment

Your lab environment is hosted on Cisco dCloud and has been pre-provisioned for this session. You will access it through **Cisco eXpo**, which provides instant access to running lab pods.

### 1.1 Connect to Your Lab Pod

1. Open a web browser on your workstation
2. Navigate to the **Cisco eXpo** portal (URL provided by your instructor)
3. Click **Get Started** to be assigned an available lab pod
4. Once assigned, you will see the **Session View** displaying your topology and connection details

### 1.2 Connectivity to the lab

If you are at Cisco Live, you should have direct access to your lab network without VPN. However, if you need to VPN into the lab:

1. Click the topology icon in the top center bar, switching from the default list view.
2. Click the info menu item right below the topology button
3. Expand Cisco Secure Client Credentials, and use this information to establish a VPN connection with Cisco Secure Client.
4. This will put you on the network that can access the 198.18.1.x/24 network, which is our management network. You should be able to ping 198.18.1.200.

---

## Step 2: Configure Router Syslog

In this step, you will configure router R3 to send syslog messages to Splunk. These syslog messages will be used to trigger automated workflows when interface state changes occur.

### 2.1 Connect to Router R3

1. Open **PuTTY** or your favorite terminal from your workstation
2. SSH to router R3:

```sh
ssh cisco@198.18.1.103
Password: cisco
```

### 2.2 Configure Syslog

Enter configuration mode and apply the following configuration:

```cisco
enable
configure terminal

! Enable syslog at debugging level to capture interface events
logging trap debugging

! Include hostname in syslog messages for identification
logging origin-id hostname

! Set source interface to mgmt interface
logging source-interface GigabitEthernet3

! Configure Splunk as the syslog destination
logging host 198.18.1.210

! Optional: you may want to set the timestamps for logging and debugging:
service timestamps log datetime msec
service timestamps debug datetime msec 

end
write memory
```

### 2.3 Verify Syslog Configuration

```cisco
show logging
```

Confirm that:
- Logging trap level is set to **debugging**
- Logging host **198.18.1.210** is listed

---

## Step 3: Setting up Splunk syslog ingestion

Now we need to get the syslog data from the router into splunk.

We must create a place for the syslog messages to be stored within Splunk, so let's first create an index to store all of our syslog data. We will use an app to extend splunk to ingest Cisco syslog with [Add-on for Cisco Network Data](https://splunkbase.splunk.com/app/1467) which gives us the cisco:ios sourcetype for data parsing. We have also pre-installed the [Cisco Networks](https://splunkbase.splunk.com/app/1352) app if you want to take advantage of syslog visualizations/trending from this data, but that is beyond the intent of this course.

### 3.1 Create a syslog index

1. In a web browser, login to http://198.18.1.210:8000 with admin / cisco
2. Setup an index by going to: **Settings> Data> Indexes**. Click the **New** index button in the upper right corner.
3. Set the index **name** to `syslog` and the **App** to `Cisco Networks`
4. Click **Submit**.

### 3.2 Setup splunk to listen to syslog

We need to ensure Splunk is listening for syslog traffic.

1. Go to **Settings> Data> Data inputs> UDP**.
2. In upper right, click **New Local UDP**. Configure the listener for UDP, port 514. Hit **Next**.
3. Set the **App context** to `Cisco Networks`, **Host method** as `IP`, **index** to `syslog`.
4. Click **Review** and validate your configuration then click **Submit**.

> **Tip:**
> You have the **expires** and **trigger conditions** to control an event state machine within Splunk. This is handy for when you may have flapping/thrashing events, where you may not want to run a workflow every time the event occurs. For this lab, we will keep it simple and trigger every time we see the event, and expire events after 5 minutes.

The configuration we have done so far gets the events into Splunk, but does not yet trigger any outbound webhooks to automation. Before we can set that up, we need to work backwards from Cisco Workflows and set some API keys up, so let's park our work in Splunk for a minute.

---

## Step 4: Setting up a workflow and webhooks in Cisco Workflows

If you want to work in your own private instance of Cisco Workflows, you can signup for an account at [meraki.cisco.com](https://meraki.cisco.com) with your email address.

If you want to use our demo instance, we will provide you with access and you will share the space with others, each creating individual workflows within the tenant organization instance.

1. Login to [meraki.cisco.com](https://meraki.cisco.com).
2. You will see an **Automation** section in the left sidebar, which is where we will mostly spend our time. This is the Cisco Workflows app.
3. Go to **Automation> Rules** and then click the **Webhooks** section in the header bar and click **Add new webhook**.
4. Name the webhook `<your_name>-splunk-webhook`. Keep the content type as `application-json` and click **Save**.
5. Click back into the webhook you just created. You should now see the **Webhook API Key** and **Webhook URL** populated. Stash these in a notepad--we will need to put them back in Splunk in a minute.

---

## Step 5: Building a basic response workflow

Here we will first build a basic workflow to acknowledge that we can get an event to trigger a workflow. It won't do any troubleshooting/repair just yet.

### 5.1 Creating a new Workflow
1. Click on **Automation> Workspace> New Workflow**. Click the **+ Create** button in the upper right, and choose `Workflow with Automation Rule` since we will be attaching a webhook rule to this workflow.
2. Name it `<your_name>-int-notify` and set the **rule type** to `webhook rule`.
3. In the left are prebuilt modules you can use to call functions. Let's send a Webex message when we trigger an alert. Under **Activities> Cisco Webex> Webex - Send Message to Person** and drag this box into the workspace canvas.
4. Open a new tab. We will come back to this in a minute, but need to register for a Webex API key now.

### 5.2 Setting up a Webex API account

We need to setup a webex API before we can finish wiring up our workflow notification.

1. Sign in to the [Webex Developer Portal](https://developer.webex.com/login)
2. In the upper right, click your photo/avatar, and choose **Create a new app**.
3. Select **Bot** since we just need to send/receive messages.
4. Name your bot `workflows-lab` and set the username to something globally unique across all Webex users like `<your_name>-<company_name>-workflows-bot`. You must select an icon to submit. Feel free to upload a fun robot icon if you desire. Click **Add bot**.
5. Copy your **Bot access token** and **Bot ID** to a safe place.

### 5.2.5 Create a Webex Space for Notifications

Create a Webex space where the bot will send notifications. You will use this space throughout the remaining labs.

1. Open Webex (app or web at https://web.webex.com)
2. Click **+** to create a new space
3. Name the space `<your_name>-workflows-lab`
4. Add your bot to the space by typing its username (e.g., `<your_name>-<company_name>-workflows-bot@webex.bot`)
5. Note the space name - you will use this in later labs for AI Agent notifications

### 5.3 Adding the webex integration

1. Go to **Automation> Variables** and click the **+ Create** button in the upper right.
2. Name the key `<yourName>-webex`, set **String Type** to `Secure String` and put the webex bearer token in the value. Click **Save**.
3. Go back to our workflow in **Automation> Workspace> *your_workflow_name***. Click the name of the workflow and Click **View Workflow** on the lower right hand corner.
4. Click on the **Webex Send Message** activity box, then in **Access Token** click the 'variable icon' on the right of the text box and select **Global> *your_access_token***.
5. Put your webex account email address in the **Recipient Email** box, and put `# It worked!` in the **Markdown Message** box. Hit enter for a new line and then click the variable icon to the right and also add the variable **Rule> Webhook Rule> Output> Request Headers**. This will take the JSON from the webhook and send it in a Webex Teams message.
6. Under Target, choose **Override workflow target** and click the **+** to add a new target. Create an **HTTP endpoint** with protocol of `HTTPS` and **host address** for `webexapis.com`. Set the **No account keys** to `True` and check **Disable server certification validation** and click **Save**.
7. You should now be able to click **Validate**, and **Run** in the upper right and receive a message in your Webex Teams.

Yay, your first workflow has been created and tested!
 
---

## Step 6: Hooking the workflow up to a webhook

Now let's hook the webhook up, so we can trigger our test message from a device's syslog event.

### 6.1 Setting up the Meraki automation rule

1. Go to **Automation> Rules> Add automation rule**
2. Set type to **webhook rule** and title it `Syslog: %LINEPROTO-5-UPDOWN`
3. Set the selected **Webhook** to the webhook you just created.
4. Apply to the workflow you just created: `<your_name>-int-notify` and click **Save**.

### 6.2 Finishing the Splunk webhook alert

Now we need to setup alerts for interesting syslog messages to trigger webhooks into Cisco Workflows for response.

We do this with a saved search that triggers a webhook. Splunk doesn't have flexible customization with webhook authentication by default, so we will leverage the installed app [Better Webhooks](https://splunkbase.splunk.com/app/7450) to define a webhook in the authentication format Cisco Workflows expects.

1. Go back to Splunk, and in the upper bar click **Apps> Better Webhooks**.
2. On the **Credentials** page, click **+New Credential**.
3. Set **Credential type** to `Custom HTTP Header` and **Header Name** as `Authorization` and put your Cisco Workflows API key in the **Header Value** and click **Submit**.
4. We will use a saved search to match Splunk criteria and trigger the webhook. Now go back to the **Settings> Knowledge> Search, alerts, and reporting** and let's create an alert.
5. Click **Settings> Knowledge> Searches, Alerting, and Reports**.
6. **IMPORTANT!** Make sure you change the **App context** in the upper header to `Cisco Networks` before creating the alert, so it associates to the right app's index.
7. Click **New Alert** in the upper right.
8. Set the inputs to the following and save it:
    - **Title:** `%LINEPROTO-5-UPDOWN webhook`
    - **Search:** `index=syslog "%LINEPROTO-5-UPDOWN" "changed state to down"`
    - **App:** `Cisco Networks`
    - **Alert type:** `Real-time`
    - **Trigger alert when:** `Per-Result`
    - **Trigger Actions:** `Better Webhook`

> **Troubleshooting tip:**
> You may want to also add a **Trigger action** for `Add to Triggered Alerts` so that you can troubleshoot that the alert generates by looking in **Activity> Triggered Alerts**. It will not log to there unless this is configured.

---

## Step 7: Testing the event triggering workflow

### 7.1 Shutdown an interface

1. You can generate a test syslog message by shutting down the loopback0

```cisco
clear logging
enable
configure terminal
interface Loopback0
shutdown
```

This should produce a new log as seen in `show logging` with contents of `%LINEPROTO-5-UPDOWN`.


### 7.2 Validation

1. View the results of the `index=syslog "%LINEPROTO-5-UPDOWN"` saved search from the **Searches, Reports, and Alerts** page, by clicking **Run**. Be sure to change the search scope (right of search bar) from `Real-time` to `All-time` to see historical results. You may need to wait a couple minutes for the event to get picked up and indexed. We generally see end-to-end processing for this lab in about 60 seconds from device syslog generation.
2. If you see interface results in the saved search, now let's see if the webhook triggered a workflow in Cisco Workflows. In Meraki, go to **Automation> Run Monitoring** and see if you see your workflow run. You can click it and go to **View run details** in the lower right. Click the Webex activity box and you will be able to see the payload of the syslog message that was sent to Webex.
3. Hopefully by now you also received a webex message with JSON payload of the syslog event. Notice some extra info in here, that the Cisco Networks app is doing some parsing magic on, since it can recognize and parse the syslog format.

If you aren't seeing end to end notification, try and isolate where the messaging is not making it. We find it useful to first start at Splunk, and then decide if you need to troubleshoot within these logical areas of the flow:

* IOS syslog logging or Splunk data ingestion, or
* Search/reporting/webhook in Splunk, or
* Workflows webhook & automation rule.

To help isolate, you can look at Splunks saved search to see if the syslog is picked up by Splunk, and the **Activity> Triggered Alerts** page to see if the webhook went out to Cisco Workflows.

---

## Summary

You have successfully configured the foundational infrastructure for agentic network operations:

| Component | Status | Purpose |
|-----------|--------|---------|
| dCloud Lab | Connected | Provides isolated lab environment |
| Router Syslog | Configured | Sends interface events to Splunk |
| Splunk Webhook | Active | Triggers Cisco Workflows on interface down events |
| Cisco Workflows | Active | Workflow sends notification of event to Webex Teams |

In the next lab, you will configure the Cisco Workflows agent to analyze incoming events and take automated remediation actions, instead of just being notified.
