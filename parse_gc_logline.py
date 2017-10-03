#!/usr/bin/env python
# Extract named XML elements from a GlobalCollect log
# usage: parse_gc_logline.py COUNTRYCODE CURRENCYCODE AMOUNT EMAIL < gc.log
import xml.etree.ElementTree as ET
import re
import sys

for line in sys.stdin:
    xml = re.search('<XML>.*</XML>', line)
    if xml is None:
        continue
    output = []
    root = ET.fromstring(xml.group(0))
    for tag in sys.argv[1:]:
        val = root.find('.//' + tag)
        if val is None:
            output.append('-')
        else:
            output.append(val.text)
    print '\t'.join(output)
