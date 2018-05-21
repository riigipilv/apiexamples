#!/bin/sh -e
# -*- coding: utf-8; indent-tabs-mode: nil; tab-width: 4; -*-
##
# Stops and deletes virtual machine instance using Waldur API.
#
#
# Requires: httpie, jq

http_opts="--check-status --ignore-stdin --print b"
waldur_api_url="https://api.riigipilv.ee"
auth_token="YOUR_AUTHENTICATION_TOKEN"


if [ $# -lt 2 ]; then
    echo "Usage: $(basename $0) <instance-name> <project-name>"
    exit 1
fi

instance_name="$1"
project_name="$2"

instances=$(http $http_opts GET "$waldur_api_url/api/openstacktenant-instances/" \
    Authorization:"token $auth_token" \
    name=="$instance_name" project_name=="$project_name"
)

instance_count=$( echo $instances | jq '. | length')

if [ $instance_count -ne 1 ]; then
    echo "Incorrect number of instances with name '${instance_name}' found" \
          "in project '${project_name}', expecting 1, found ${instance_count}."
    exit 1
fi

instance_url=$( echo $instances | jq -r '.[0].url')

if [ -z "$instance_name" -o "$instance_url" = "null" ]; then
    echo "[ERROR] Instance '$instance_name' not found." >&2
    exit 1
fi

echo "Shutting down instance '$instance_name'..."
http $http_opts POST "${instance_url}stop/" \
    Authorization:"token $auth_token" \
    | jq -r '.status' | sed 's/^/Waldur response: /'
for i in $(seq 12); do
    printf "."
    sleep 10
    instance_state=$(http $http_opts GET "$instance_url" \
        Authorization:"token $auth_token" \
        name=="$instance_name" \
        | jq -r '.runtime_state')
    if [ "$instance_state" = "SHUTOFF" ]; then
        echo "";
        break
    fi
done
if [ "$instance_state" != "SHUTOFF" ]; then
    echo "[WARNING] Failed to shut down instance '$instance_name', instance state: '$instance_state'." >&2
    #exit 1  # do not exit yet, attempt to delete instance first
fi

echo "Deleting instance '$instance_name'..."
http $http_opts DELETE "$instance_url" \
    Authorization:"token $auth_token" \
    | jq -r '.status' | sed 's/^/Waldur response: /'
for i in $(seq 12); do
    printf "."
    sleep 10
    instance_data=$(http $http_opts GET "$instance_url" \
        Authorization:"token $auth_token" \
        name=="$instance_name" \
        | jq -r '.')
    echo $instance_data | grep -q 'Not found' && break
    if [ -z "$instance_data" ]; then
        echo ""
        break
    fi
done

# check result, if GET lookup still doesn't return 404 => problem
if http $http_opts GET "$instance_url" Authorization:"token $auth_token" &> /dev/null; then
    echo "[ERROR] Failed to delete instance '$instance_name'"
    exit 1
fi

echo "Instance '$instance_name' deleted successfully."