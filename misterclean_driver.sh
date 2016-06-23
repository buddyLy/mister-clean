#!/bin/bash

function email_offender_list
{
	servername=$(hostname)

	#sed '/^\s*$/d' test.txt | wc -l
	if [ -e ${report_repeated_offenders} ]; then
		#count only non blank lines
		rowcount=$(cat ${report_repeated_offenders} | sed '/^\s*$/d' | wc -l)
		[ $rowcount -ne 0 ] && cat ${report_repeated_offenders} | mailx -s "${servername} Repeated offenders" ${support_email}
	fi

	if [ -e ${report_sorted_badusers} ]; then
		#count only non blank lines
		rowcount=$(cat ${report_sorted_badusers} | sed '/^\s*$/d' | wc -l)
		[ $rowcount -ne 0 ] && cat ${report_sorted_badusers} | mailx -s "${servername} Bad users report" ${support_email}
	fi
}

function is_weekend
{
	#monday=1, friday is 5, any date greater than 5 is weeekend
	if [[ $(date +%u) -gt 5 ]];then
		return "${TRUE}"
	else
		return "${FALSE}"
	fi
}

function start_for_real
{
	while (( 1 ));do
		local sleep_hrs=6
		#do not run on weekend
		is_weekend 
		if [[ $? -eq "${FALSE}" ]];then
			exit 1;
			main && email_offender_list
			echo "$(date) sleeping for ${sleep_hrs} hrs"
			sleep_time=$(echo "${sleep_hrs} * 60 * 60" | bc)
			sleep "${sleep_time}"
			echo "$(date) waking after sleeping for ${sleep_time} seconds"
		else
			echo "still the weekend, not running"
			sleep_time=$(echo "${sleep_hrs} * 60 * 60" | bc)
			sleep "${sleep_time}"
		fi
	done
}



function start_one_time
{
	main && email_offender_list
}

source misterclean.cfg
source misterclean.sh
start_for_real

