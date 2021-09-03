#!/bin/sh
[ $# -ge 1 -a -f "$1" ] && input="$1" || input="-"
sed -e 's/\\//g' $input | /usr/bin/python -mjson.tool
