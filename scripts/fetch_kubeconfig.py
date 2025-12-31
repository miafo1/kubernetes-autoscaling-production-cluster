#!/usr/bin/env python3
import sys
import time
import json
import subprocess
import base64
import gzip
import io

def run_command(cmd):
    try:
        # Run command and capture output
        result = subprocess.run(cmd, shell=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return result.stdout.decode('utf-8').strip()
    except subprocess.CalledProcessError as e:
        print(f"Error running command: {cmd}")
        print(e.stderr.decode('utf-8'))
        sys.exit(1)

def main():
    if len(sys.argv) < 4:
        print("Usage: fetch_kubeconfig.py <REGION> <INSTANCE_ID> <PUBLIC_IP>")
        sys.exit(1)

    region = sys.argv[1]
    instance_id = sys.argv[2]
    public_ip = sys.argv[3]

    print(f"Fetching Kubeconfig via SSM from {instance_id} ({public_ip}) in {region}...")

    # 1. Send Command (GZIP + Base64 encoded to fit in SSM 2500 char limit)
    # k3s.yaml is ~3KB. SSM truncates at 2.5KB.
    # Gzipping reduces it to ~800 bytes.
    cmd_string = "sudo cat /etc/rancher/k3s/k3s.yaml | gzip | base64 -w 0"
    
    # Construct AWS CLI command
    send_cmd = f'aws ssm send-command --region {region} --instance-ids {instance_id} --document-name "AWS-RunShellScript" --parameters "commands=[\'{cmd_string}\']" --output json'
    
    send_output = run_command(send_cmd)
    try:
        command_id = json.loads(send_output)['Command']['CommandId']
    except (KeyError, json.JSONDecodeError) as e:
        print("Failed to parse send-command output.")
        print(send_output)
        sys.exit(1)

    print(f"SSM Command ID: {command_id}. Waiting for execution...")

    # 2. Wait for completion
    status = "Pending"
    retries = 0
    max_retries = 90 # 3 minutes approx
    
    output_content = ""
    
    while status not in ["Success", "Failed", "Cancelled", "TimedOut"]:
        if retries > max_retries:
            print("Timeout waiting for SSM command.")
            sys.exit(1)
        
        time.sleep(2)
        
        list_cmd = f'aws ssm list-command-invocations --region {region} --command-id {command_id} --details --output json'
        list_output = run_command(list_cmd)
        
        try:
            invocations = json.loads(list_output).get('CommandInvocations', [])
            if not invocations:
                retries += 1
                continue
                
            status = invocations[0]['Status']
            
            if status == "Success":
                output_content = invocations[0]['CommandPlugins'][0]['Output']
                break
            elif status in ["Failed", "Cancelled", "TimedOut"]:
                print(f"Command failed with status: {status}")
                print(invocations[0]['CommandPlugins'][0]['Output'])
                sys.exit(1)
            else:
                 if retries % 5 == 0:
                    print(f"Status: {status}...")
                
        except (KeyError, IndexError, json.JSONDecodeError):
            pass
            
        retries += 1

    # 3. Decode and Save
    if not output_content:
        print("Error: SSM Output is empty.")
        sys.exit(1)

    try:
        b64_str = output_content.strip()
        compressed_bytes = base64.b64decode(b64_str)
        # Decompress
        decoded_bytes = gzip.decompress(compressed_bytes)
        yaml_content = decoded_bytes.decode('utf-8')
    except Exception as e:
        print("Error decoding/decompressing output:")
        print(e)
        print("Raw output start:", output_content[:50])
        sys.exit(1)

    # Replace localhost with Public IP
    yaml_content = yaml_content.replace('127.0.0.1', public_ip)

    # Write to file
    with open('k3s.yaml', 'w') as f:
        f.write(yaml_content)

    print("Success! Kubeconfig saved to k3s.yaml")
    print(f"Run: export KUBECONFIG=$(pwd)/k3s.yaml")

if __name__ == "__main__":
    main()
