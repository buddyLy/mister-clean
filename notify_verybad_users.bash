#!/bin/bash

function is_sandbox_env
{
	local myserver=$(hostname)
	isDev && return ${FALSE}
	isProd && return ${FALSE}

	#if it gets here, than it's sandbox
	return ${TRUE}
}

function is_valid_user
{
	local myuserid=$1
	is_sandbox_env	
	if [[ $? -eq ${FALSE} ]];then
		adquery user ${myuserid} || return ${FALSE}
		return ${TRUE}
	else
		echo "is sandbox, not checking user"
	fi
}

function send_reason_mail
{
	local myuserid=$1
	shift
	local mysize=$1

	local myenv="sandbox" 
	local myserver=$(hostname)
	isDev
	if [[ $? -eq ${TRUE} ]]; then
		myenv="Dev6"
	else
		isProd
		if [[ $? -eq ${TRUE} ]]; then
			myenv="Prod6"
		fi
	fi
	
	local badfiles=$(du -h ${myuserid})

	msg="You have surpassed your limit in your user directories on ${myenv}. Due to the limited space on this mount, users expected to not exceed 300Megs.
Please create your own directory here /u/applic/data/hdfs1/<your user name> and move your files over, then remove it after you are done with it.
---------USAGE DETAILS-------
environment: ${myenv}
server: ${myserver}
user: ${myuserid}
your size: ${mysize}G
limit: 300M
tmp location: /u/applic/data/hdfs1/${myuserid}
---------FILE SIZE DETAILS-------
${badfiles}"

	subject="WARNING: You are over limit on file size"

	#TODO: get first and last name using adquery
	is_valid_user ${myuserid} || return ${FALSE}

	#do not send email on process id
	if [[ ${myuserid} != "svcckp" && ${myuserid} != "svcckppi" && ${myuserid} != "svccmt" ]];then
		if [[ ${notify_user}  -eq ${TRUE} ]];then
			echo "Notifying space usage to ${myuserid}"
			#echo "${msg}" | mailx -s "${subject}" ${myuserid}@wal-mart.com 
		else
			echo "Notifying space usage to ${support_email}"
			#echo "${msg}" | mailx -s "${subject}" ${support_email} && return ${TRUE}
		fi
	fi
}

function readfile_into_array
{
	local myfile=$1
	nbr_of_users=()	
	
	IFS=$'\n' read -d '\n' -r -a report_array < ${myfile} 
	unset IFS

	#find offenders users by provided date
	for line in ${report_array[*]}; do
		local parsedwords=($(echo ${line} | tr '|' "\n"))	
		local theuser=${parsedwords[0]}
		
		nbr_of_users+=("${theuser}")
	done

	echo "suspected users:\n ${nbr_of_users[*]}"
}

function is_user_still_bad
{
	local myuser=$1
	#local size=$(du -h "${myuser}" 2>/dev/null| awk '{print $1}')
	local size=$(du -s ${myuser} 2>/dev/null| awk -v limit=${user_total_limit} 'BEGIN{} {if($1>limit) {$1=$1/(1024*1024);print $0}}') 
	if [[ ${size} != "" ]]; then
		#send_reason_mail "${myuser}" "${size}"
		echo "${myuser} is still bad"
		return ${TRUE}
	else
		echo "${myuser} is still good"
		return ${FALSE}
	fi
}


function check_user
{
	user_still_bad_list=()
	#recreat the user still bad list by looping through current list and check each user
	for eachuser in ${nbr_of_users[*]}; do
		#for each user that is still bad, add that user back into the still bad list
		is_user_still_bad ${eachuser} && user_still_bad_list+=(${eachuser})
	done

	echo "still bad users:\n ${user_still_bad_list[*]}"
}

function check_user_still_bad
{
	user_still_bad_list_tmp=()
	for eachuser in ${user_still_bad_list[*]}; do
		is_user_still_bad ${eachuser} && user_still_bad_list_tmp+=(${eachuser}) 
	done

	#reinitialize user still bad list
	user_still_bad_list=()
	for x in ${user_still_bad_list_tmp[*]};do
		user_still_bad_list+=("$x")	
	done

	if (( ${#user_still_bad_list[*]} == 0 ));then
		return ${FALSE}
	else
		echo "returning still bad users:\n ${user_still_bad_list[*]}"
		return ${TRUE}
	fi
}

function main
{
	source misterclean.cfg
	source util_func.sh

	sleep_hrs=5
	sleep_time=$(echo "${sleep_hrs} * 60 * 60" | bc)
	sleep_time=$(echo "${sleep_hrs} * 1 * 1" | bc)
	user_still_bad_list=()
	readfile_into_array "verybadusers.txt"

	if [[ ${#nbr_of_users[*]} -ne 0 ]];then
		check_user
		while (( ${#user_still_bad_list[*]} != 0 ));do
			check_user_still_bad && echo "sleeping"; sleep ${sleep_time}
			date
			echo "waking up"
		done
	fi
}

main
