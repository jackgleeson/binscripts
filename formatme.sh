#!/bin/bash
# Sort input by timestamp, pretty-print arrays and XML, skip blank lines
sort -k2,3 - | sed -e 's/\(<\/[^>]*>\)/\1\n/g' | sed -e 's/#012/\n/g' | sed -e '/^\s*$/d' | less
