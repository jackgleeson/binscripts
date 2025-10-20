#!/bin/bash

# --- Configuration ---
host="frqueue1003.frack.eqiad.wmnet"
password="password"
key_pattern="gravy_error_threshold_*"

# --- Argument Parsing ---
show_members=false
if [[ "$1" == "--all" ]]; then
  show_members=true
fi

# --- Script Logic ---
cursor=0
while true; do
  # Use SCAN to iterate over keys matching the pattern
  reply=$(redis-cli -h "$host" -a "$password" SCAN "$cursor" MATCH "$key_pattern" 2>/dev/null)

  # Extract cursor and keys from the multi-line reply
  cursor=$(echo "$reply" | head -n 1)
  keys_found=$(echo "$reply" | tail -n +2)

  echo "$keys_found" | while read -r key; do
    if [ -n "$key" ]; then
      # Extract the timestamp part of the key
      timestamp_part=$(echo "$key" | grep -oE '[0-9]+$')

      # Calculate the full Unix timestamp (assuming the part is a divisor of the full timestamp)
      # NOTE: This conversion logic is preserved from the original script
      unix_timestamp=$((timestamp_part * 1800))

      # Convert timestamp to human-readable date
      datetime=$(date -d "@$unix_timestamp" +"%Y-%m-%d %H:%M:%S %Z")

      # Now handle keys based on the --all flag
      if $show_members; then
        # Use HGETALL to get all field/value pairs from the Hash
        echo "$datetime | $key:"
        # HGETALL returns field then value on alternating lines.
        # sed is used here to format the output with indents.
        redis-cli -h "$host" -a "$password" HGETALL "$key" 2>/dev/null |
          paste -d: - - |
          sed 's/^/  - /'
      else
        # Default behavior: use HLEN to get the count of fields in the Hash
        value=$(redis-cli -h "$host" -a "$password" HLEN "$key" 2>/dev/null)
        echo "$datetime | $key: ($value fields)"
      fi
    fi
  done

  # Break the loop when the cursor returns to 0
  if [ "$cursor" -eq 0 ]; then
    break
  fi
done
