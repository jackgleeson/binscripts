#!/bin/bash
# Inefficiently get the first occurrence of each email address in a log file
cmd=grep
if [ ${1: -3} == ".gz" ]
then
  cmd=zgrep
fi
EMAILS=`$cmd -Eo '\w+@\w+\.\w+' $1 | sort | uniq`
for i in $EMAILS
do
  $cmw -m1 $i $1 
done
