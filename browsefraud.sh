#!/bin/bash
# List details of recent rejected GlobalCollect payments
# To be run from the remote log directory
for i in `grep reject payments-fraud | cut -d' ' -f 6 | cut -d ':' -f 1 | sort | uniq`
do
	grep $i payments-globalcollect | grep '<REQUEST><ACTION>INSERT_ORDERWITHPAYMENT' | parse_gc_logline.py COUNTRYCODE CURRENCYCODE AMOUNT FIRSTNAME SURNAME EMAIL
	grep $i payments-fraud | grep CustomFiltersSco
done
