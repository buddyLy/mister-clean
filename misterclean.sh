#!/bin/bash
##===================================================================
#shell scripts functionality
#* alert if /u is bigger % full with only x size left
#* alert if each user directory is more than x size
#* alert if each applicaiton directory is more than x size
#* alert if there exist a script that's been running longer than x
#* find files bigger than x
#* find files older than x
#* which group id belongs to
#	- depending on id, go to appropriate hdfs folder
#* move files to folder
#* send report/emails to users
#* find hdfs .trash files bigger than x
#* find hdff .trash files older than x
#* each hdfs mount shoudld not bet
#* identify repeated offenders
#** leaverage what Dan already has in his script that generates the report
#** leaverage the monitoring
#** leaverage shell script from hadoop dba
#https://wiki.wal-mart.com/index.php/Hadoop_Space_Management
##============================================================


#whois
#id
#logger utility
#adquery
#groups

function check_config_variable
{
	log_msg "${LINENO} ENTERING FUNCTION" "${LOGGER_INFO}"
	get_current_time
	local log_header=${current_time}${DELIMITER}${process_id}${DELIMITER}${this_script}${DELIMITER}${FUNCNAME[0]}${DELIMITER}$
	#-----constants------#	
	# got to error exit result of expression is false
	[[ -n "${TRUE}" ]] || error_exit "${log_header}${LINENO}: Config constants not set. rc $?"
	[[ -n "${FALSE}" ]] || error_exit "${log_header}${LINENO}: Config constants irectory not set. rc $?"
	[[ -n "${SUCCESS}" ]] || error_exit "${log_header}${LINENO}: Config constants not set. rc $?"
	[[ -n "${ERROR}" ]] || error_exit "${log_header}${LINENO}: Config constants not set. rc $?"

	#-----directory structure------#	
	[[ -n "${home}" ]] || error_exit "${log_header}${LINENO}: Config directory structure not set. rc $?"
	#isDirectory ${home} || error_exit "${log_header}${LINENO} Home directory doesn't exist"
	[[ -n "${logdir}" ]] || error_exit "${log_header}${LINENO}: Config directory structure not set. rc $?"
	#isDirectory ${logdir} || mkdir -p ${logdir}	|| error_exit "${log_header}${LINENO}: Config directory structure not set. rc $?" #if log folder doesn't exist, then create it
	
	#-----program options------#	
	[[ -n "${clean_hdfs}" ]] || error_exit "${log_header}${LINENO}: Config program options not set. rc $?"
	[[ -n "${clean_local}" ]] || error_exit "${log_header}${LINENO}: Config program options not set. rc $?"

	#-----program variables------#	
	[[ -n "${logfile}" ]] || error_exit "${log_header}${LINENO}: Config program variables not set. rc $?"
	isFile "${logfile}" || touch ${logdir}/${logfile} || error_exit "${log_header}${LINENO}: error creating logfile. rc $?"
	[[ -n "${logfile_error}" ]] || error_exit "${log_header}${LINENO}: Config program variables not set. rc $?"
	isFile "${logfile_error}" || touch ${logdir}/${logfile_error} || error_exit "${log_header}${LINENO}: Config error creating logfile. rc $?"
}


function set_config_env_var
{
	is_sandbox_env
	if [[ $? -eq ${TRUE} ]];then
		user_total_limit=${user_total_limit_sandbox}
		processid_total_limit=${processid_total_limit_sandbox}
		user_basedir=${user_basedir_sandbox}
		logdir=${logdir_sandbox}
		home=${home_sandbox}
	fi
}

function initialize
{
	#captures error on commands that piped together, can also retrieved through ${PIPESTATUS[0]} ${PIPESTATUS[1]}

	source ./misterclean.cfg || error_exit "${LINENO} ERROR Error source file doesn't exist"
	source ./util_func.sh || error_exit "${LINENO} ERROR Error source file doesn't exist"

	#set the correct environment variable by environment
	set_config_env_var
	
	process_id=$$
	main_script=$(basename $0)
	this_script=${BASH_SOURCE[0]}
	verify_unix_shell ${supported_os}
	if [[ $? -ne ${SUCCESS} ]];then
		os_is_supported=${FALSE}
		#if bypass warning is false, then exit program
		if (( !bypass_warning )); then
			error_exit "${FUNCNAME[0]}${DELIMITER}${LINENO} ERROR Unsupported unix version";
		fi
	else
		os_is_supported=${TRUE}
	fi
}

function get_main_logheader
{
	get_current_time
	function_name=${FUNCNAME[1]} #this will store the function name of the direct caller
	log_header=${current_time}${DELIMITER}${process_id}${DELIMITER}${this_script}${DELIMITER}${function_name}${DELIMITER}
}

function check_userdir_permission
{
	log_msg "${LINENO} ENTERING FUNCTION" "${LOGGER_INFO}"
	local userdir=$1
	if [[ ${os_is_supported} -eq ${TRUE} ]];then
		filemode=$(stat -c %a "${user_basedir}/${user}" || echo "error")
		if [[ ${filemode} == "error" ]]; then
			error_exit "${LINENO} ERROR Error getting user permission"
		fi
	else
		filemode=$(stat -f "%Lp" "${user_basedir}/${user}" || echo "error")
		if [[ ${filemode} == "error" ]]; then
			error_exit "${LINENO} ERROR Error getting user permission"
		fi
	fi

	#get the user permissino of group and other
	group_other_permission=${filemode:1:2}	#the last two digits
	if [[ ${group_other_permission} == "77" || ${group_other_permission} == "55" ]];then
		return ${SUCCESS}
	else
		return ${ERROR}
	fi
}

function sort_report
{
	local direction=$1; shift
	local delimiter=$1; shift
	local sorted_column=$1;
	
	sort --${direction} -t "${delimiter}" -k ${sorted_column} ${home}/${report_file} > ${home}/${report_sorted_badusers} || error_exit "${LINENO} ERROR. Error sorting report"
}

#generate bad users report
function generate_badusers_report
{
	log_msg "${LINENO} ENTERING FUNCTION" "${LOGGER_INFO}"
	local myreport=$1	
	#spit out the report to a file
	log_msg "Generating bad users report to ${home}/${report_file}. Nbr of bad users found: ${#bad_user_list[*]}" "${LOGGER_INFO}"
	echo -e "${myreport}" >> ${home}/${report_file}

	#sort by user size
	#echo -e "${myreport}" > ${home}/${report_file}.tmp && sort --reverse -t "|" -k 3 ${home}/${report_file} > ${home}/${report_sorted_badusers}
	echo -e "${myreport}" > ${home}/${report_file}.tmp && sort_report ${report_sorted_direction} ${report_sorted_delimiter} ${report_sorted_column}
}

#generate user error report
function generate_usererror_report
{
	log_msg "${LINENO} ENTERING FUNCTION" "${LOGGER_INFO}"
	#write all users that weren't querable into an error file
	if [[ ${#query_usererror_list[*]} -ne 0 ]];then
		get_current_time
		#zero out the report
		echo "" > ${home}/${report_file_error}
		echo "${current_time} The following users were unquerable" >> ${home}/${report_file_error}		
		for user in ${query_usererror_list[*]}; do
			echo ${user} >> ${home}/${report_file_error}		
		done
	fi
}

function get_bad_users
{
	log_msg "${LINENO} ENTERING FUNCTION" "${LOGGER_INFO}"
	#for all users found, find users that's over limit
	query_usererror_list=()
	bad_user_list=()
	invalid_user_list=()

	#if user has other file permission as 55 or 77, then go through with du
	#else add to file permission error

	#search for directories over limit
	for user in $(ls -F ${user_basedir} 2>>${logdir}/${logfile_error} | grep "/" 2>>${logdir}/${logfile_error} || echo "error")
	do
		if [[ ${user} == "error" ]];then
			log_msg "${LINENO} ERROR Error getting list of users"
			return ${FALSE}
		fi
	
		#if user doesn't give permission, move to next user
		check_userdir_permission ${user}
		if [[ $? -eq ${ERROR} ]];then
			log_msg "${LINENO} WARNING Potential issues while querying user ${user}"
			query_usererror_list+=("${user}|${filemode}")
			continue
		fi
		
		#if user id process id, then a different size restriction
		log_msg "Checking user ${user}" "${LOGGER_INFO}"

		#strip out last slash of userid such as lcle/
		is_process_id ${user%?}
		if [[ $? -eq ${TRUE} ]];then
			local bad_user=$(du -s ${user_basedir}/${user} 2>>${logdir}/${logfile_error}| awk -v limit=${processid_total_limit} 'BEGIN{} {if($1>limit) {$1=$1/(1024*1024);print $0}}' 2>>${logdir}/${logfile_error})
		else
			local bad_user=$(du -s ${user_basedir}/${user} 2>>${logdir}/${logfile_error}| awk -v limit=${user_total_limit} 'BEGIN{} {if($1>limit) {$1=$1/(1024*1024);print $0}}' 2>>${logdir}/${logfile_error})
		fi
		#if bad user is returned, then add to bad user report
		if [[ ${bad_user} != "" ]];then
			#variables below are used to write out to the report
			local parsed_word=(${bad_user})	
			size=${parsed_word[0]}
			#strip out the last slash in user directory name
			userid=${user%?}
			date=$(date +%m-%d-%y)
			
			#write value to the report using double redirection
			generate_report "${#report_columns_array[*]}" "${!report_columns_array[0]}" "${!report_columns_array[1]}" "${!report_columns_array[2]}"

			#send email to the users that are over size limit
			send_reason_mail ${userid} ${size}
			[[ $? -eq ${FALSE} ]] && invalid_user_list+=(${userid})

			log_msg "Adding user ${user} to bad list" "${LOGGER_INFO}"
			#bad_users="${bad_users} ${user}"
			bad_user_list+=(${user})
		fi
	done

	#generate report
	generate_badusers_report ${report}

	#generate error report
	generate_usererror_report
}

function get_listofbadfiles_peruser
{
	log_msg "${LINENO} ENTERING FUNCTION" "${LOGGER_INFO}"
	local user=$1
	echo "get list of bad files for user ${user}"
	#IFS=$'\n' #separate by line
	#find all files greater than max_file_size and older than retention period
	#find ~/tmp/users/user1 -size +13M -atime +0d -type f -print0 | xargs -0 ls); do echo $x; myarray+=($x); done; echo "length: ${#myarray[@]}
	#using xargs on print0 to prevent files with crazy separator messing up the file storage in an array
	local cmd="find ${user_basedir}/${user} -size +${max_file_size} -atime +${retention_period}d -type f -print0 2>>${logfile_error} | xargs -0 ls 2>>${logfile_error}"
	#list_of_bad_files=$(find ${user_basedir}/${user} -size +${max_file_size} -atime +${retention_period}d -type f -print0 | xargs -0 ls || echo "error")
	#local bad_files=$(${cmd} || echo "error")
	local bad_files=$(find ${user_basedir}/${user} -size +${max_file_size} -atime +${retention_period}d -type f -print0 2>>${logdir}/${logfile_error} | xargs -0 ls 2>>${logdir}/${logfile_error} || echo "error")
	bad_file_list=()
	if [[ ${bad_files} == "error" ]];then
		echo "Error executing command: ${cmd}"
		return ${FALSE}
	else
		#make an array from return values
		IFS=$'\n'
		for file in ${bad_files}; do
			#echo "putting file in list: $file"
			bad_file_list+=("${file}")	
		done
		unset IFS
	fi
}

function is_file_old
{
	log_msg "${LINENO} ENTERING FUNCTION" ${LOGGER_INOF}
	myfile=$1	
	space_in_mb=$(du -m ${myfile} | awk '{print $1}') || error_exit "${LINENO} Error file getting file size"
	#if [[ ${space_in_mb} -gt ${max_file_size} ]];then
		#is file greater than x days
		oldfile=$(find ${myfile} -atime +${retention_period}d -type f -ls | wc -l || return "error")
		if [[ ${list_of_old_files} == "error" ]];then
			return ${ERROR}
		else
			echo "here are the lsit of old files for user $"
		fi
	#fi
	return ${FALSE}
}

#notify users of all files that are over the maximum allowed
function notify_bad_users
{
	local file=$1
	shift
	local user=$2
	msg="Hey ${user}, Your file ${file} is over the size limit and has been moved here. Please direct any questions to lcle@wal-mart.com"
	echo "${msg}"
	#echo "Your file ${file} is over size limit and has been moved here"| mailx -s "Your space usage in $server exceeds the 300MB limit" lcle@wal-mart.com
}

function notify_admin
{
	log_msg "${LINENO} ENTERING FUNCTION" "$LOGGER_INFO"
	local bad_users=("${!1}")
}

function generate_report
{
	local array_size=$1	
	local j
	#write out each field value. notice it's using the double redirection to get the actual value of the variable name instead of the name of the string
	for (( j=0; j<${array_size}; j++ ));do
		shift
		local column_value=$1
		report="${report}${column_value}|"
	done
	report="${report}\n"
	#echo -e "report so far: \n$report"
}

function initialize_report
{
	#make an array out of the report headers
	IFS="," && report_columns_array=(${report_columns}) || return ${FALSE}
	report=""
	unset IFS
}

function isCompared
{
	local compared_value=$1
	for eachvalue in ${already_compared[*]}; do
		if [[ ${compared_value} == ${eachvalue} ]];then
			return ${TRUE}
		fi
	done
	return ${FALSE}
}

#read the the last x days into an array, if x = 0, then all lines in the file into array
function readfile_into_array
{
	local myfile=$1
	suspected_users=()	
	#if [[ $? -eq ${SUCCESS} ]];then
	if [[ ${os_is_supported} -eq ${TRUE} ]];then
		#linux bash date implementation
		local daysago=$(date --date="${report_days_back} days ago" ${report_date_format} || echo "error")
		if [[ ${daysago} == "error" ]];then
			error_exit "${LINENO} ERROR calculating days back"
		fi
	else
		#darwin bash date implementation
		local daysago=$(date -j -v-${report_days_back}d ${report_date_format} || echo "error")
		if [[ ${daysago} == "error" ]];then
			error_exit "${LINENO} ERROR calculating days back"
		fi
	fi
	
	local founddate=${FALSE}
	IFS=$'\n' read -d '\n' -r -a report_array < ${myfile}
	#|| error_exit "${LINENO} Error putting bad users report into array"
	unset IFS

	#find offenders users by provided date
	for line in ${report_array[*]}; do
		local parsedwords=($(echo ${line} | tr '|' "\n"))	
		local thedate=${parsedwords[0]}
		local theuser=${parsedwords[1]}
		local thesize=${parsedwords[2]}
		
		#skip the first line
		if [[ $thedate == "date" ]];then
			continue
		fi
		
		#echo "line: $line ~ date: $thedate theuser: $theuser"
		if [[ ${founddate} -eq ${FALSE} ]];then
			if [[ ${daysago} != ${thedate} ]]; then
				continue
			else
				founddate=${TRUE}
			fi
		fi
		#echo "putting to list: ${thedate}|${theuser}|${thesize}"
		suspected_users+=("${thedate}|${theuser}|${thesize}")
	done

	if [[ ${#suspected_users[*]} -eq 0 ]];then
		#error_exit "${LINENO} ERROR Please check nbr of days back, it might go beyond report kept date or report of bad user is empty"
		log_msg "${LINENO} WARNING Please check nbr of days back, it might go beyond report kept date or report of bad user is empty"
		return ${ERROR}
	fi
	echo "suspected users:\n ${suspected_users[*]}"
}

function generate_repeatedoffenders_report
{
	local offenders_report=""
	for each_offender in ${repeated_offenders[*]};do
		offenders_report="${offenders_report}${each_offender}|\n"
	done
	echo "Generating offenders report: ${home}/${report_repeated_offenders}"
	echo -e "${offenders_report}" > ${home}/${report_repeated_offenders}
}

function find_repeated_offenders
{
	#loop through each user and find repeated offenders
	already_compared=()
	repeated_offenders=()
	for eachuser in ${suspected_users[*]}; do
		local usercount=0
		local parsedwords=($(echo ${eachuser} | tr '|' "\n"))
		local theuser=${parsedwords[1]}

		#go to next loop if the user has already been compared
		isCompared "${theuser}"
		[[ $? -eq ${TRUE} ]] && continue

		#add to the list of already been compared
		already_compared+=("${theuser}")
		
		#loop thru same array and count up the nbr of times on the bad list
		for each_in_report in ${suspected_users[*]};do
			local parsedwords2=($(echo ${each_in_report} | tr '|' "\n"))	
			local theuser2=${parsedwords2[1]}
			if [[ $theuser == $theuser2 ]];then
				(( usercount++ ))				
			fi
		done

		local offended_user="${theuser}|${usercount}"
		repeated_offenders+=("$offended_user")
	done

	echo "here are the repeated offenders\n: ${repeated_offenders[*]}"
	generate_repeatedoffenders_report
}

function check_user_spaceusage
{
	log_msg "${LINENO} ENTERING FUNCTION" "${LOGGER_INFO}"

	#initilize to start a brand new report
	initialize_report
	[[ $? -eq ${FALSE} ]] && error_exit "${LINENO} ERROR Error getting report header"
	
	#for each user that has passed their limit, check each files and move
	get_bad_users
	[[ $? -eq ${FALSE} ]] && error_exit "${LINENO} Error getting list of bad users"

	#read the bad users report into an array
	readfile_into_array ${home}/${report_file}
	#if error is returned, there's a possibility that the report hasn't kept the history long enough, in that case, do for all instead of date range
	if [[ $? -eq ${ERROR} ]];then
		report_days_back=0
		log_msg "${LINENO} Recalling function to read into array without date range"
		readfile_into_array ${home}/${report_file}
	fi

	#find repeated offenders
	find_repeated_offenders
}

function check_user_spaceusage_two
{
	log_msg "${LINENO} ENTERING FUNCTION" "${LOGGER_INFO}"
	#for each user that has passed their limit, check each files and move
	get_bad_users || error_exit "${LINENO} Error getting list of bad users"
	
	#echo "bad user list: ${bad_user_list}"
	initialize_report || error_exit "${LINENO} ERROR Error getting report header"

	#for each bad users, get the files that are over limit
	for eachuser in ${bad_user_list[@]}
	do
		userid=${eachuser}
		file_list_peruser=() #clear out the current list
		#get list of files for each user
		get_listofbadfiles_peruser ${eachuser} || error_exit "${LINENO} Error getting list of files over limit"
		
		echo "length is: ${#bad_file_list[@]}"
		for eachfile in "${bad_file_list[@]}"
		do
			file="${eachfile}"
			size=$(du -h "${file}" 2>>${logdir}/${logfile_error}| awk '{print $1}' 2>>${logdir}/${logfile_error} || echo "error")
			if [[ ${size} == "error" ]];then
				error_exit "${LINENO} ERROR Error file size"
			fi

			file_list_peruser+=(${eachfile})
			#move_file_out ${eachfile}
			#notify_bad_users ${eachfile} ${eachuser}
			#the ! points to the value of the variable
			generate_report "${#report_columns_array[*]}" "${!report_columns_array[0]}" "${!report_columns_array[1]}" "${!report_columns_array[2]}"
		done
		#notify_admin ${eachuser} file_list_peruser[@]
	done
	#spit out the report to a file
	echo -e "${report}" > ${home}/${report_file}
}

function check_user_group
{
	log_msg "${LOG_HEADER} ENTERING FUNCTION ${LOGGER_INOF}"
	user=$1
	id ${user}
	#do something here to get the group of the user belongs to
}

function move_file_out
{
	log_msg "${LINENO} ENTERING FUNCTION ${LOGGER_INOF}"

	#check_user_group
	if [[ ${group} == "MEP" ]];then
		echo "moving to MEP hdfs folder"
	elif [[ ${group} == "CKP" ]];then
		echo "moving to CKP hdfs folder"
	elif [[ ${group} == "CIQ" ]];then
		echo "moving to CIQ hdfs folder"
	else
		echo "moving files to somwhere"
	fi	
}	

function is_sandbox_env
{
	local myserver=$(hostname)
	isDev
	if [[ $? -eq ${TRUE} ]];then
		return ${FALSE}
	fi
	
	isProd
	if [[ $? -eq ${TRUE} ]];then
		return ${FALSE}
	fi

	#if it gets here, than it's sandbox
	return ${TRUE}
}

#is valid user
function is_valid_user
{
	local myuserid=$1
	is_sandbox_env	
	if [[ $? -eq ${FALSE} ]];then
		adquery_result=$(adquery user ${myuserid} 3>>${home}/${report_invalid_userids} || echo "error")
		if [[ ${adquery_result} == "error" || ${adquery_result} == "" ]];then
			#not_valid_user+=(${myuserid})
			#echo "${myuserid}" >> ${home}/${report_invalid_userids}
			return ${FALSE}
		else
			unset IFS
			adquery_parsed=($(echo ${adquery_result} | tr ':' "\n"))
			first_name=${adquery_parsed[4]}
			last_name=${adquery_parsed[5]}
			name_from_id="${first_name} ${last_name}"
			return ${TRUE}
		fi
	else
		echo "Sandbox detected, not checking for valid user"
		return ${FALSE}
	fi
}

function is_process_id
{
	local user=$1
	local processids=("svcdidc" "svcckp" "svcckppi" "svccmt" "bfdsys" "globaml" "svcpkp" "svcckpdv")
	#looping through array to verify whether the user is a process id
	for processid in ${processids[*]}; do
		[[ ${user} == ${processid} ]] && return ${TRUE}
	done

	return ${FALSE}
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
	
	#strip out the last character because it contain slash /
	is_valid_user ${myuserid}
	[[ $? -eq ${FALSE} ]] && return ${FALSE}

	#list all files for that user
	local badfiles=$(du -h ${user_basedir}/${myuserid})

	msg="${name_from_id}, you have surpassed your limit in your user directories on ${myenv}. Due to the limited space on this mount, users expected to not exceed 300Megs.
Please create your own directory here /u/applic/data/hdfs1/<your user name> and move your files over, then remove it after you are done with it. Please direct any questions to lcle@wal-mart.com.
---------USAGE DETAILS-------
environment: ${myenv}
server: ${myserver}
user: ${myuserid}
your size: ${mysize}G
limit: 300M
tmp location: /u/applic/data/hdfs1/${myuserid}
---------FILE SIZE DETAILS-------
${badfiles}"

	subject="WARNING ${name_from_id}: You are over limit on file size"

	#do not send email on process id
	#if [[ ${myuserid} != "svcckp" && ${myuserid} != "svcckppi" && ${myuserid} != "svccmt" && ${myuserid} != "bfdsys" && ${myuserid} != "globaml" && ${myuserid} != "svcpkp" ]];then
	is_process_id ${myuserid}
	if [[ $? -eq ${FALSE} ]];then
		if [[ ${notify_user}  -eq ${TRUE} ]];then
			echo "${msg}" | mailx -s "${subject}" "${myuserid}@wal-mart.com, ${support_email}"
		else
			echo "Notifying space usage to ${support_email}"
			echo "${msg}" | mailx -s "${subject}" ${support_email} && return ${TRUE}
		fi
	else
		echo "User is process id. Not sending mail: ${myuserid}"
		return ${FALSE}
	fi
}

function cleanup_after_yourself
{
	retain_lastx_log_size ${logdir}/${logfile} ${log_retention_line:-100000}
	retain_lastx_log_size ${logdir}/${logfile_error} ${log_retention_line:-100000}
	retain_lastx_log_size nohup.out ${log_retention_line:-100000}
}	

function get_local_offenders
{
	log_msg "${LINENO} ENTERING FUNCTION" "${LOGGER_INFO}"
	has_enough_space "${mount_space_needed}" "${mount_location}"
	if [[ $? == ${FALSE} ]];then
		alert_me "${FUNCNAME[0]}${DELIMITER}${LINENO} ERROR Insufficient space on ${mount_location}"
	fi

	check_user_spaceusage || return ${FALSE}
	cleanup_after_yourself
	return ${SUCCESS}
}

function is_user_still_bad
{
	local user=$1
	is_process_id ${user%?}
	if [[ $? -eq ${TRUE} ]];then
		local bad_user=$(du -s ${user_basedir}/${user} 2>>${logdir}/${logfile_error}| awk -v limit=${processid_total_limit} 'BEGIN{} {if($1>limit) {$1=$1/(1024*1024);print $0}}' 2>>${logdir}/${logfile_error})
	else
		local bad_user=$(du -s ${user_basedir}/${user} 2>>${logdir}/${logfile_error}| awk -v limit=${user_total_limit} 'BEGIN{} {if($1>limit) {$1=$1/(1024*1024);print $0}}' 2>>${logdir}/${logfile_error})
	fi
	
	user=${user%?}
	#if a size is returned, it means they are still violated so do not remove them the list
	if [[ ${bad_user} != "" ]]; then
		unset IFS
		local parsed_word=(${bad_user})	
		size=${parsed_word[0]}
		#size=$(echo "${bad_user}" | awk '{print $1}')
		send_reason_mail "${user}" "${size}"
		return ${TRUE}
	else
		#remove user from bad list
		echo "removing users ${user} from ${home}/${report_sorted_badusers}"
		sed -i "/${user}/d" ${home}/${report_sorted_badusers} || error_exit "$LINENO ERROR removing good users from bad use list"
		sed -i "/${user}/d" ${home}/${report_file} || error_exit "$LINENO ERROR removing good users from bad use list"
		return ${FALSE}
	fi
}


function check_user
{

	user_still_bad_list=()
	#recreat the user still bad list by looping through current list and check each user
	for eachuser in ${suspected_users[*]}; do
		IFS="|" && thisuserarray=(${eachuser})
		thisuser="${thisuserarray[1]}/"	
		#for each user that is still bad, add that user back into the still bad list
		is_user_still_bad ${thisuser} && user_still_bad_list+=(${thisuser})
	done
	unset IFS

	echo "still bad users:\n ${user_still_bad_list[*]}"
}

function check_user_still_bad
{
	user_still_bad_list_tmp=()
	for eachuser in ${user_still_bad_list[*]}; do
		#add back all the users that are still bad
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

#take the user off the list once back to limit
function notify_verybad_users
{
	sleep_hrs=${continuous_alert_hrs}
	#convert to hours
	sleep_time=$(echo "${sleep_hrs} * 60 * 60" | bc)
	#sleep_time=$(echo "${sleep_hrs} * 1 * 1" | bc)
	user_still_bad_list=()
	#readfile_into_array "verybadusers.txt"
	
	report_days_back=0
	readfile_into_array "${report_sorted_badusers}"
	#if [[ ${#nbr_of_users[*]} -ne 0 ]];then
	if [[ ${#suspected_users[*]} -ne 0 ]];then
		check_user
	fi

	#continuously checking until the bad user list reduces to zero
	if [[ ${continuous_alert} -eq ${TRUE} ]];then
		echo "sleeping...checking again in ${sleep_hrs} hours" 
		sleep ${sleep_time}
		while (( ${#user_still_bad_list[*]} != 0 ));do
			check_user_still_bad && echo "sleeping for ${sleep_hrs} hrs"; sleep ${sleep_time}
		done
	fi
}

#TODO: need to finish out this function to check for application directory
function check_appdir
{
	for application in $(du -h --maxdepth=2 /u/applic 2>>${logdir}/${logfile_error}| awk -v limit=1000000 'BEGIN{} {if($1>limit) {$1=$1/(1024*1024);print $0}}' 2>>${logdir}/${logfile_error})
	#du -h -d 2
	do
		if [[ ${application} == "error" ]];then
			log_msg "${LINENO} ERROR Error getting list of applications"
			return "${FALSE}"
		fi
	done
}

#main
function main
{
	#initialize all necessary variales for scrip to run properly
	initialize

	log_msg "*********STARTING misterclean***********"

	#ensure all required variales are set
	#TODO - add variables
	check_config_variable

	#find users who are reaching limit
	get_local_offenders|| error_exit "${LINENO} ERROR Error cleaning local"

	#take the user off the list once back to limit
	notify_verybad_users
	
	log_msg "*********ENDING misterclean***********"
}

#script >${logdir}/${logfile} 2>${logdir}/${logfile_error}
#main

######################################################
#UNIT TESTING STARTS HERE
#This unit testing will not execute under these conditions:
# 	- if sourced, ie, sourced by another program
#	- called by another program.
#Unit test cases will execute if run this shell script by itself
######################################################
(
	#bash_source at 0 holds the actual name, if kicked off from another program, base_source is not itself, then exit
	#since we wrapped this in a subshell "( )", then it will only exit the subshell not the actual program
	[[ "${BASH_SOURCE[0]}" == "${0}" ]] || exit 0

	function init_unittest
	{
		logfile="unittest/misterclean_unittest.log"
		logfile_error="unittest/misterclean_error_unittest.log"
		unittest_file="unittest/unit_test.log"
		report_file_error="unittest/report_error.txt"
		report_file="unittest/baduser_unittest_report.txt"
		report_repeated_offenders="unittest/repeated_offenders.txt"
		local mydate=$(date)
		echo "******Starting unit tests at ${mydate}*******" > ${unittest_file}
	}
	
	function assertEquals
	{
		msg=$1; shift
		expected=$1; shift
		actual=$1; shift
		/bin/echo -n "$msg: " >> ${unittest_file}
		if [ "$expected" != "$actual" ]; then
			echo "FAILED: EXPECTED=$expected ACTUAL=$actual" >> ${unittest_file}
		else
			echo "PASSED" >> ${unittest_file}
		fi
	}

	#if user over 300M limit, send email
	function send_email_on_moved_file_test
	{
		echo "Testing ${FUNCNAME[0]}" >> ${unittest_file}
		assertEquals ">>>TEST ${FUNCNAME[0]}" ${FALSE} ${TRUE}
	}

	#get user to the correct group
	function retrieve_user_group_test
	{
		echo "Testing ${FUNCNAME[0]}" >> ${unittest_file}
		assertEquals ">>>TEST ${FUNCNAME[0]}" ${FALSE} ${TRUE}
	}
	
	#read into an array
	function readfile_into_array_test
	{
		echo "Testing ${FUNCNAME[0]}" >> ${unittest_file}
		report_file="unittest/badusers_unittest.txt"
		
		rm ${home}/${report_file}
		echo "11-12-15|user2|5GB" >> ${home}/${report_file}
		echo "11-13-15|user1|6GB" >> ${home}/${report_file}
		echo "11-14-15|user2|6GB" >> ${home}/${report_file}
		echo "11-15-15|user1|6GB" >> ${home}/${report_file}
		echo "11-16-15|user1|6GB" >> ${home}/${report_file}
		echo "11-17-15|user1|6GB" >> ${home}/${report_file}
		echo "11-18-15|user3|6GB" >> ${home}/${report_file}

		#add latest date in there, and test to make sure it has at least 1 date
		local mydate=$(date +%m-%d-%y)
		echo "${mydate}|user3|6GB" >> ${home}/${report_file}
	
		report_days_back=0
		readfile_into_array "${home}/${report_file}"
		#sed will exclude blank lanes
		#local file_line_count=$(cat ${home}/${report_file} | sed '/^\s*$/d' | wc -l)
		local file_line_count=1
		local arraysize=${#suspected_users[*]}
		#if there's at least 1, ie, <= 1, which is accomplished by negation
		if [[ ! ${file_line_count} -gt ${arraysize} ]];then
			local RETURN_CODE=${TRUE}
		else
			RETURN_CODE=${FALSE}
		fi
		assertEquals ">>>TEST ${FUNCNAME[0]}" ${TRUE} ${RETURN_CODE}
	}

	#retrieve users that crosses limit
	function get_bad_users_test
	{
		echo "Testing ${FUNCNAME[0]}" >> ${unittest_file}
		user_total_limit=100
		user_basedir="unittest/users"
		initialize_report
		get_bad_users
		#if there exist at least 1 user in the list, then the query is successful
		if [[ ${#bad_user_list[*]} -eq 4 ]];then
			if [[ ${#query_usererror_list[*]} -gt 0 ]];then
				local RETURN_CODE=${TRUE}
			else
				RETURN_CODE=${FALSE}
			fi
		else
			RETURN_CODE=${FALSE}
		fi
		assertEquals ">>>TEST ${FUNCNAME[0]}" ${TRUE} ${RETURN_CODE}
	}

	function get_listofbadfiles_peruser_test
	{
		echo "Tessting ${FUNCNAME[0]}" >> ${unittest_file}
		max_file_size="1M"
		retention_period="1"	
		local user="user2"

		get_listofbadfiles_peruser "$user"
		#if there exist at least 1 user in the list, then the query is successful
		if [[ ${#bad_file_list[*]} -gt 0 ]];then
			local RETURN_CODE=${TRUE}
		else
			RETURN_CODE=${FALSE}
		fi
		assertEquals ">>>TEST ${FUNCNAME[0]}" ${TRUE} ${RETURN_CODE}
	}

	function find_repeated_offenders_test
	{
		echo "Testing ${FUNCNAME[0]}" >> ${unittest_file}
		suspected_users=("11-17-2015|user1/|0.139481|" "11-17-2015|user2/|0.164787|" "11-17-2015|user2/|0.164787|" "11-17-2015|user1/|0.164787|" "11-17-2015|user3/|0.164787|")
		find_repeated_offenders
		if [[ ${#repeated_offenders[*]} -eq 3 ]];then
			local RETURN_CODE=${TRUE}
		else
			RETURN_CODE=${FALSE}
		fi
		assertEquals ">>>TEST ${FUNCNAME[0]}" ${TRUE} ${RETURN_CODE}
	}

	function send_reason_mail_test
	{
		echo "Testing ${FUNCNAME[0]}" >> ${unittest_file}
		send_reason_mail "lcle" "300000"
		RETURN_CODE=$?
	
		EXPECTED=${TRUE}
		#if sandox, then cannot check using adquery, always return false
		is_sandbox_env
		if [[ $? -eq ${TRUE} ]];then
			EXPECTED=${FALSE}
		fi
	
		assertEquals ">>>TEST ${FUNCNAME[0]}" ${EXPECTED} ${RETURN_CODE}
	}

	function send_reason_mail_processid_test
	{
		echo "Testing ${FUNCNAME[0]}" >> ${unittest_file}
		send_reason_mail "svcckp" "300000"
		RETURN_CODE=$?
		assertEquals ">>>TEST ${FUNCNAME[0]}" ${FALSE} ${RETURN_CODE}
	}

	function is_valid_user_test
	{
		echo "Testing ${FUNCNAME[0]}" >> ${unittest_file}
		is_valid_user "lcle"
		RETURN_CODE=$?
		
		EXPECTED=${TRUE}

		#if sandox, then cannot check using adquery, always return false
		is_sandbox_env
		if [[ $? -eq ${TRUE} ]];then
			EXPECTED=${FALSE}
		fi

		assertEquals ">>>TEST ${FUNCNAME[0]}" ${EXPECTED} ${RETURN_CODE}
	}
	
	function is_valid_user_not_valid_test
	{
		echo "Testing ${FUNCNAME[0]}" >> ${unittest_file}
		#init array
		not_valid_user=()
		is_valid_user "lcle1"
		RETURN_CODE=$?
		
		EXPECTED=${FALSE}
		#if sandox, then cannot check using adquery, always return false
		is_sandbox_env
		if [[ $? -eq ${TRUE} ]];then
			EXPECTED=${FALSE}
		fi
		assertEquals ">>>TEST ${FUNCNAME[0]}" ${EXPECTED} ${RETURN_CODE}
	}

	function is_process_id_test
	{
		echo "Testing ${FUNCNAME[0]}" >> ${unittest_file}
		is_process_id "svcckp"
		rc=$?
		EXPECTED=${TRUE}
		ACTUAL=${rc}
		assertEquals ">>>TEST ${FUNCNAME[0]}" ${EXPECTED} ${ACTUAL}
	}

	function is_process_id_false_test
	{
		echo "Testing ${FUNCNAME[0]}" >> ${unittest_file}
		is_process_id "lcle"
		rc=$?
		EXPECTED=${FALSE}
		ACTUAL=${rc}
		assertEquals ">>>TEST ${FUNCNAME[0]}" ${EXPECTED} ${ACTUAL}
	}

	function generate_badusers_report_test
	{
		echo "TODO"
	}

	function is_user_still_bad_test
	{
		echo "Testing ${FUNCNAME[0]}" >> ${unittest_file}
		report_sorted_badusers="unittest_sorted_badusers.txt"
		user_total_limit=300
		
		rm ${home}/${report_sorted_badusers}
		echo "11-12-15|user2/|5GB" >> ${home}/${report_sorted_badusers}
		echo "11-13-15|user1/|6GB" >> ${home}/${report_sorted_badusers}
		echo "11-14-15|user2/|6GB" >> ${home}/${report_sorted_badusers}
		echo "11-15-15|user1/|6GB" >> ${home}/${report_sorted_badusers}
		echo "11-16-15|user4/|6GB" >> ${home}/${report_sorted_badusers}
		echo "11-17-15|user1/|6GB" >> ${home}/${report_sorted_badusers}
		echo "11-18-15|user3/|6GB" >> ${home}/${report_sorted_badusers}

		user_basedir="./unittest/users"
		mkdir -p ${user_basedir}/user4 || error_exit "Error executing unit test"
		/bin/rm ${user_basedir}/user4/*
		cp ${user_basedir}/user1/* ${user_basedir}/user4/ || error_exit "${LINENO} Error executing test case"

		is_user_still_bad "user4/"
		rc=$?
		EXPECTED=${TRUE}
		ACTUAL=${rc}
		assertEquals ">>>TEST ${FUNCNAME[0]}" ${EXPECTED} ${ACTUAL}

		local count=$(cat ${home}/${report_sorted_badusers} | wc -l)
		rc=${FALSE}
		if [[ ${count} -eq 7 ]];then
			rc=${TRUE}
		fi
		EXPECTED=${TRUE}
		ACTUAL=${rc}
		assertEquals ">>>TEST ${FUNCNAME[0]}" ${EXPECTED} ${ACTUAL}
	}
	
	function is_user_still_bad_false_test
	{
		echo "Testing ${FUNCNAME[0]}" >> ${unittest_file}
		report_sorted_badusers="unittest_sorted_badusers.txt"
		
		rm ${home}/${report_sorted_badusers}
		echo "11-12-15|user2/|5GB" >> ${home}/${report_sorted_badusers}
		echo "11-13-15|user1/|6GB" >> ${home}/${report_sorted_badusers}
		echo "11-14-15|user2/|6GB" >> ${home}/${report_sorted_badusers}
		echo "11-15-15|user1/|6GB" >> ${home}/${report_sorted_badusers}
		echo "11-16-15|user4/|6GB" >> ${home}/${report_sorted_badusers}
		echo "11-17-15|user1/|6GB" >> ${home}/${report_sorted_badusers}
		echo "11-18-15|user3/|6GB" >> ${home}/${report_sorted_badusers}

		user_basedir="./unittest/users"
		mkdir -p ${user_basedir}/user3 || error_exit "Error executing unit test"
		/bin/rm ${user_basedir}/user3/*
		echo "test not back to normal space" > ${user_basedir}/user3/file1.txt || error_exit "${LINENO} Error executing test case"
		
		is_user_still_bad "user3/"
		rc=$?
		EXPECTED=${FALSE}
		ACTUAL=${rc}
		assertEquals ">>>TEST ${FUNCNAME[0]}" ${EXPECTED} ${ACTUAL}

		local count=$(cat ${home}/${report_sorted_badusers} | wc -l)
		rc=${FALSE}
		if [[ ${count} -eq 6 ]];then
			rc=${TRUE}
		fi
		EXPECTED=${TRUE}
		ACTUAL=${rc}
		assertEquals ">>>TEST ${FUNCNAME[0]}" ${EXPECTED} ${ACTUAL}
	}

	function check_user_still_bad_test
	{
		#data setup
		echo "Testing ${FUNCNAME[0]}" >> ${unittest_file}
		report_sorted_badusers="unittest_sorted_badusers.txt"
		user_total_limit=300
		
		rm ${home}/${report_sorted_badusers}
		echo "11-12-15|user2/|5GB" >> ${home}/${report_sorted_badusers}
		echo "11-13-15|user1/|6GB" >> ${home}/${report_sorted_badusers}
		echo "11-16-15|user4/|6GB" >> ${home}/${report_sorted_badusers}
		echo "11-18-15|user3/|6GB" >> ${home}/${report_sorted_badusers}

		user_basedir="./unittest/users"
		mkdir -p ${user_basedir}/user3 || error_exit "Error executing unit test"
		/bin/rm ${user_basedir}/user3/*
		echo "test not back to normal space" > ${user_basedir}/user3/file1.txt || error_exit "${LINENO} Error executing test case"
	
		mkdir -p ${user_basedir}/user4 || error_exit "Error executing unit test"
		/bin/rm ${user_basedir}/user4/*
		cp ${user_basedir}/user1/* ${user_basedir}/user4/ || error_exit "${LINENO} Error executing test case"

		#set user_still_bad_list array list
		user_still_bad_list=("user3/" "user4/")
		#this will check in above list and output the users that are still bad
		check_user_still_bad
		local count=${#user_still_bad_list[*]}

		[[ ${count} -eq 1 ]] && rc=${TRUE} || rc=${FALSE}
		EXPECTED=${TRUE}
		ACTUAL=${rc}
		assertEquals ">>>TEST ${FUNCNAME[0]}" ${EXPECTED} ${ACTUAL}
	}


	function notify_verybad_users_test
	{
		notify_verybad_users
	}


	#test all functions
	initialize
	init_unittest
	#get_bad_users_test
	#readfile_into_array_test
	#find_repeated_offenders_test
	#is_valid_user_test
	#is_valid_user_not_valid_test
	#send_reason_mail_test
	#send_reason_mail_processid_test
	#is_process_id_test
	#is_process_id_false_test
	is_user_still_bad_test
	is_user_still_bad_false_test
	check_user_still_bad_test
	#notify_verybad_users_test

	#TODO test cases
	#generate_badusers_report_test
	
	#send_email_on_moved_file_test
	#retrieve_user_group_test
	#move_files_over_limit_test
	#get_listofbadfiles_peruser_test	
	#get_file_size_test
	#get_file_age_test
	#file_with_space_test
	echo "-------UNIT TEST RESULT-----"

	cat ${unittest_file}
)


