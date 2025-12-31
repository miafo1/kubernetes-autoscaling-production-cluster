#!/bin/bash
set -e

REGION=$1
INSTANCE_ID=$2
PUBLIC_IP=$3

echo "Fetching Kubeconfig via SSM from Instance $INSTANCE_ID ($PUBLIC_IP) in $REGION..."

# 1. Execute Command
CMD_ID=$(aws ssm execute-command \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --commands "sudo cat /etc/rancher/k3s/k3s.yaml" \
    --query "Command.CommandId" \
    --output text)

echo "SSM Command ID: $CMD_ID. Waiting for execution..."

# 2. Wait for completion (Simple polling)
STATUS="Pending"
RETRIES=0
while [ "$STATUS" != "Success" ]; do
    if [ $RETRIES -gt 20 ]; then
        echo "Timeout waiting for SSM command."
        exit 1
    fi
    sleep 2
    STATUS=$(aws ssm list-command-invocations \
        --region "$REGION" \
        --command-id "$CMD_ID" \
        --details \
        --query "CommandInvocations[0].Status" \
        --output text)
    echo "Status: $STATUS"
    RETRIES=$((RETRIES+1))
    
    if [ "$STATUS" == "Failed" ]; then
        echo "SSM Command Failed (Possible reasons: Agent not online yet, UserData still running, or permission issue)."
        # Print error
        aws ssm list-command-invocations \
            --region "$REGION" \
            --command-id "$CMD_ID" \
            --details \
            --query "CommandInvocations[0].CommandPlugins[0].Output" \
            --output text
        exit 1
    fi
done

# 3. Retrieve Output
aws ssm list-command-invocations \
    --region "$REGION" \
    --command-id "$CMD_ID" \
    --details \
    --query "CommandInvocations[0].CommandPlugins[0].Output" \
    --output text > k3s.yaml

# 4. Patch Public IP
if [ -s k3s.yaml ]; then
    sed -i "s/127.0.0.1/$PUBLIC_IP/g" k3s.yaml
    echo "Success! Kubeconfig saved to k3s.yaml"
    echo "Run: export KUBECONFIG=$(pwd)/k3s.yaml"
else
    echo "Error: Retrieved k3s.yaml is empty."
    exit 1
fi
