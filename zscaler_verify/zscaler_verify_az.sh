#!/bin/sh
# Test Azure CLI with AZURE_CLI_DISABLE_CONNECTION_VERIFICATION
# This should work once the env var is set in .certificates

az rest \
  --method get \
  --uri "https://app.vssps.visualstudio.com/_apis/accounts?memberId=me&api-version=7.1" \
  --resource "499b84ac-1321-427f-aa17-267ca6975798"
