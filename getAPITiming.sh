#!/bin/bash
# Uses awk to get average durations of API calls from log files
cmd=grep
if [ ${1: -3} == ".gz" ]
then
  cmd=zgrep
fi
$cmd -F commstats $1 \
| grep -F curl_transaction \
| tr -dc '[:print:]\n' \
| sed -e 's/.*duration:\([^ ]*\).*additional:\([^ ]*\).*/\2 \1/' \
| sort -g -k 1,2 \
| awk 'BEGIN {
	txn="";
	count=0;
	print "API_call","min","max","avg","median"
}
function printit(txn, min, max, total, count,vals) {
	if (count > 0) {
		if (count % 2 == 0) {
			median = vals[count / 2];
		} else {
			median = vals[(count - 1) / 2];
		}
		print txn,min,max,total/count,median;
	}
}
{
	if (txn != $1) {
		printit(txn,min,max,total,count,vals);
		txn = $1;
		total = 0;
		count = 0;
		max = 0;
		min = 999999;
		delete vals;
	}
	vals[count] = $2;
	total += $2;
	count += 1;
	if ( $2 < min ) min = $2;
	if ( $2 > max ) max = $2;
}
END {
	printit(txn,min,max,total,count,vals);
}' \
| column -t
