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
  reply=$(redis-cli -h "$host" -a "$password" SCAN "$cursor" MATCH "$key_pattern" 2>/dev/null)

  cursor=$(echo "$reply" | head -n 1)
  keys_found=$(echo "$reply" | tail -n +2)

  echo "$keys_found" | while read -r key; do
    if [ -n "$key" ]; then
      timestamp_part=$(echo "$key" | grep -oE '[0-9]+$')

      unix_timestamp=$((timestamp_part * 1800))

      datetime=$(date -d "@$unix_timestamp" +"%Y-%m-%d %H:%M:%S %Z")

      # Now handle keys based on the --all flag
      if $show_members; then
        # Use SMEMBERS to get all members
        echo "$datetime | $key:"
        redis-cli -h "$host" -a "$password" SMEMBERS "$key" 2>/dev/null | sed 's/^/  - /'
      else
        # Default behavior: use SCARD to get the count
        value=$(redis-cli -h "$host" -a "$password" SCARD "$key" 2>/dev/null)
        echo "$datetime | $key: ($value items)"
      fi
    fi
  done

  if [ "$cursor" -eq 0 ]; then
    break
  fi
done
