#!/usr/bin/env python3

from radkit_client.sync import Client

with Client.create() as client:
  client.sso_login(domain="PROD")
  client.enroll_client()
  print('done')