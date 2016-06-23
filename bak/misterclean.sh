#!#/bin/bash
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
	isDirectory ${home} || error_exit "${log_header}${LINENO} Home directory doesn't exist" 
	[[ -n "${logdir}" ]] || error_exit "${log_header}${LINENO}: Config directory structure not set. rc $?"
	isDirectory ${logdir} || mkdir -p ${logdir}	|| error_exit "${log_header}${LINENO}: Config directory structure not set. rc $?" #if log folder doesn't exist, then create it
	
	#-----program options------#	
	[[ -n "${clean_hdfs}" ]] || error_exit "${log_header}${LINENO}: Config program options not set. rc $?"
	[[ -n "${clean_local}" ]] || error_exit "${log_header}${LINENO}: Config program options not set. rc $?"

	#-----program variables------#	
	[[ -n "${logfile}" ]] || error_exit "${log_header}${LINENO}: Config program variables not set. rc $?"
	isFile "${logfile}" || touch ${logdir}/${logfile} || error_exit "${log_header}${LINENO}: error creating logfile. rc $?"
	[[ -n "${logfile_error}" ]] || error_exit "${log_header}${LINENO}: Config program variables not set. rc $?"
	isFile "${logfile_error}" || touch ${logdir}/${logfile_error} || error_exit "${log_header}${LINENO}: Config error creating logfile. rc $?"
}

function initialize
{
	#captures error on commands that piped together, can also retrieved through ${PIPESTATUS[0]} ${PIPESTATUS[1]}
	set -o pipefail	
	source ./misterclean.cfg || error_exit "${LINENO} ERROR Error source file doesn't exist"
	source ./util_func.sh || error_exit "${LINENO} ERROR Error source file doesn't exist"
	process_id=$$
	main_script=$(basename $0)
	this_script=${BASH_SOURCE[0]}
	verify_unix_shell ${supported_shell} || error_exit "${FUNCNAME[0]}${DELIMITER}${LINENO} ERROR Unsupported unix version"
}

function get_main_logheader
{
	get_current_time
	function_name=${FUNCNAME[1]} #this will store the function name of the direct caller
	log_header=${current_time}${DELIMITER}${process_id}${DELIMITER}${this_script}${DELIMITER}${function_name}${DELIMITER}
}

function check_local_mount
{
	#local log_header=${current_time}${DELIMITER}${process_id}${DELIMITER}${this_script}${DELIMITER}${FUNCNAME[0]}${DELIMITER}$
	log_msg "${LINENO} ENTERING FUNCTION" "${LOGGER_INFO}"
	local check_remote_server=${FALSE}
	has_enough_space "${mount_space_needed}" "${mount_location}" "${check_remote_server}" || error_exit "${FUNCNAME[0]}${DELIMITER}${LINENO} ERROR checking for enough space $?"
}

function get_bad_users
{
	log_msg "${LINENO} ENTERING FUNCTION" "${LOGGER_INFO}"
	#for all users found, find users that's over limit 
	query_usererror_list=()
	bad_user_list=()

	#search for directories over limit
	for user in $(ls -F ${user_basedir} 2>>${logfile_error} | grep "/" 2>>${logfile_error} || echo "error")
	do
		if [[ ${user} == "error" ]];then
			log_msg "${LINENO} ERROR Error getting list of users"
			return ${FALSE}
		fi

		#myarray=();for x in $(find ~/tmp/users/user1 -size +13M -atime +0d -type f -print0 | xargs -0 ls); do echo $x; myarray+=($x); done; echo "length: ${#myarray[@]}"
		echo "checking bad user ${user}"
		local bad_user=$(du -s ${user_basedir}/${user} 2>>${logfile_error}| awk 'BEGIN{} {if($1>300000) {$1=$1/(1024*1024);print $0}}' 2>>${logfile_error} || echo "error")
		if [[ ${bad_user} == "error" ]];then
			#error_exit "${FUNCNAME[0]}${DELIMITER}${LINNO} ERROR Error getting user bad list. cmd=du -s ${user} 2>/dev/null | awk 'BEGIN{} {if($1>300000) {$1=$1/(1024*1024);print $0}}'"
			#users_with_issues="${users_with_issues}${user}\n"
			query_usererror_list+=(${user})
			echo "encountering issues query user: ${user}"
		else
			echo "adding user ${user} to bad list"
			#bad_users="${bad_users} ${user}"
			bad_user_list+=(${user})
		fi
	done

	#write all users that weren't querable into an error file
	if [[ ${#query_usererror_list[*]} -ne 0 ]];then
		local date=$(date)
		echo "Query ran on: ${date}. The following users have files unquerable" >> ${report_file_error}
		for user in ${query_usererror_list[*]}; do
			echo ${user} >> ${report_file_error}		
		done
	fi
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
	local bad_files=$(find ${user_basedir}/${user} -size +${max_file_size} -atime +${retention_period}d -type f -print0 2>>${logfile_error} | xargs -0 ls 2>>${logfile_error} || echo "error")
	bad_file_list=()
	if [[ ${bad_files} == "error" ]];then
		echo "Error executing command: ${cmd}"
		return ${FALSE}
	else
		
		#make an array from 
		IFS=$'\n'
		for file in ${bad_files}; do
			echo "putting file in list: $file"
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
			return ${FALSE}
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
	msg="Hey ${user}, Your file ${file} is over the size limit and has been moved here"
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
	for (( j=0; j<${array_size}; j++ ));do
		shift
		local column=$1
		report="${report}${column}\t"
	done
	report="${report}\n"
	#echo -e "report so far: \n$report"
}

function initialize_report
{
	IFS="," && report_columns_array=(${report_columns}) || return ${FALSE}
	unset IFS
}

function check_user_spaceusage
{
	log_msg "${LINENO} ENTERING FUNCTION" "${LOGGER_INFO}"
	#for each user that has passed their limit, check each files and move
	get_bad_users || error_exit "${LINENO} Error getting list of bad users"
	
	#echo "bad user list: ${bad_user_list}"

	#for each bad users, get the files that are over limit 

	initialize_report || error_exit "${LINENO} ERROR Error getting report header"

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
			size=$(du -h "${file}" 2>>${logfile_error}| awk '{print $1}' 2>>${logfile_error} || echo "error")
			if [[ ${size} == "error" ]];then
				error_exit "${LINENO} ERROR Error file size"
			fi

			file_list_peruser+=(${eachfile})
			#move_file_out ${eachfile}
			#notify_bad_users ${eachfile} ${eachuser}
			generate_report "${#report_columns_array[*]}" "${!report_columns_array[0]}" "${!report_columns_array[1]}" "${!report_columns_array[2]}"
		done
		#notify_admin ${eachuser} file_list_peruser[@]
	done
	echo -e "${report}" > ${report_file}
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

#function send_reason_mail
#{
#	msg="You have surpassed your limit. Your files has been moved here"
#	subject="File size alert"
#	email="lcle"
#	#get first and last name
#	echo "msg" | mailx -s "${subject}" ${email}@wal-mart.com
#}

function clean_local
{
	log_msg "${LINENO} ENTERING FUNCTION" "${LOGGER_INFO}"
	#check_local_mount
	check_user_spaceusage || return ${FALSE}
	return ${SUCCESS}
}

function clean_hdfs
{
	echo "${LOG_HEADER} ENTERING FUNCTION"
	return ${SUCCESS}
}

#main
function main
{
	initialize
	check_config_variable
	clean_local	|| error_exit "Error cleaning local" 
	#clean_hdfs || error_exit "Error cleaning hdfs" 
}

#script >${logdir}/${logfile} 2>${logdir}/${logfile_error}
#main

######################################################
#Unit Testing starts here
#This unit testing will not execute under these conditions:
# 	- if sourced, ie, sourced by another program
#	- called by another program.
#Unit test cases will execute if run this shell script by itself
######################################################
(
	#bash_source at 0 holds the actual name, if kicked off from another program, base_source is not itself, then exit
	#since we wrapped this in a subshell "( )", then it will only exit the subshell not the actual program
	[[ "${BASH_SOURCE[0]}" == "${0}" ]] || exit 0
	#mycfgfile="/my/config/file/program_config.cfg"
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
	
	#move any file over 300Megs to appropriate hdfs location
	function move_files_over_limit_test
	{
		echo "Testing ${FUNCNAME[0]}" >> ${unittest_file}
		assertEquals ">>>TEST ${FUNCNAME[0]}" ${FALSE} ${TRUE}
	}

	#retrieve users that crosses 300Megs
	function get_bad_users_test
	{
		echo "Tessting ${FUNCNAME[0]}" >> ${unittest_file}
		get_bad_users

		#if there exist at least 1 user in the list, then the query is successful
		if [[ ${#bad_user_list[*]} -gt 0 ]];then
			local rc=${FALSE}
		fi
		assertEquals ">>>TEST ${FUNCNAME[0]}" ${TRUE} ${$rc}
	}

	#get file size
	function get_file_size_test
	{
		echo "Testing ${FUNCNAME[0]}" >> ${unittest_file}
		assertEquals ">>>TEST ${FUNCNAME[0]}" ${FALSE} ${TRUE}
	}
	
	#get file age 
	function get_file_age_test
	{
		echo "Testing ${FUNCNAME[0]}" >> ${unittest_file} 
		assertEquals ">>>TEST ${FUNCNAME[0]}" ${FALSE} ${TRUE}
	}

	#what to do with directories that have small files over 300megs
		#-move directory 

	#test all functions
	initialize
	#send_email_on_moved_file_test
	#retrieve_user_group_test
	#move_files_over_limit_test
	get_bad_users_test
	#get_file_size_test
	#get_file_age_test
	#file_with_space_test
)
