#!/bin/bash

# This script takes two arguments: a gateway transaction ID and a 'Redirecting for transaction:' JSON message.
# It updates the 'gateway_txn_id' field in the redirect JSON message with the provided transaction ID.
# The script then outputs a new JSON message that can be used as a donation message.
#
# Requirements:
# - jq (https://jqlang.github.io/jq/) must be installed. You can install it using: `sudo apt install jq`
#
# Usage:
# ./redirectJson2DonationJson.sh <gateway_txn_id> <redirectJson>
#
# Example:
# ./redirectJson2DonationJson.sh "NEW_TXN_ID_HERE" '{"gateway_txn_id":false, ... }'

if [ "$#" -ne 2 ]; then
    echo "Usage: ./redirectJson2DonationJson.sh <gateway_txn_id> <redirectJson>"
    exit 1
fi

gateway_txn_id=$1
redirectJson=$2

# Update the gateway_txn_id in the JSON string and output the new JSON
echo $redirectJson | jq --arg gateway_txn_id "$gateway_txn_id" '.gateway_txn_id = $gateway_txn_id'
