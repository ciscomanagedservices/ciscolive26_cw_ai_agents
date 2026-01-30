#!/bin/bash
cd /Users/scdozier/Documents/Repos/ciscolive26_cw_ai_agents

# Stage all changes
git add lab-guide/docs/lab1.md lab-guide/docs/lab2.md lab-guide/docs/lab3.md

# Commit
git commit -m "Update lab guides: merge conflict resolution, simplified targets, and UX improvements"

# Push
git push

# Update PR description
gh pr edit 15 --body "## Summary

This PR updates Lab 1, Lab 2, and Lab 3 guides with the following changes:

### Lab 1 Changes

#### Merge Conflict Resolution
- Kept the improved Search for Room + Post Message to Room Webex approach (instead of Send Message to Person)
- Preserved the reordered structure with Webex API setup before workflow creation

#### UX Improvements
- **Section 7.2 Validation**: Made the index=syslog LINEPROTO-5-UPDOWN search text a clickable hyperlink that opens the Splunk search directly

### Lab 2 Changes

#### Simplified Step 4 - Removed Target Groups
Target groups add unnecessary complexity for this lab. Changed to use direct target override instead:

- **Step 4.3**: Replaced Configure the Workflow Target Group with simple No Target selection
- **Removed Step 4.4**: Eliminated the placeholder target group condition step entirely
- **Step 4.8**: Rewrote Override the Target Group Condition to use direct Override workflow target to R3
- Added note explaining that dynamic target selection via target groups is outside the scope of this lab
- Renumbered all subsequent steps (4.5 through 4.11)

### Lab 3 Changes

#### New Variable Verification Step
- **Section 4.3.2 Step 5**: Added instruction to verify the l_meraki_dashboard_url variable matches the users Cisco Workflows URL prefix in their browser
- Added explanatory note that this variable is used to generate clickable links in Webex notifications
- Renumbered subsequent steps (6-9)"

