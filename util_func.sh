#!/bin/bash

function turn_on_trace_mode
{
	#turning on tracing mode. 
	#turn on trace mode only when trace mode option is true 
	[[ $trace_mode -eq 1 ]] && set -x
	#PS4='$LINENO: '
	#exec 5> debug_output.txt
	#BASH_XTRACEFD="5"
	#set -x : Display commands and their arguments as they are executed.
	#set -v : Display shell input lines as they are read.
	#!/bin/bash -xv
	#_DEBUG="on"

}

#error exit due to fatal error
function error_exit
{
	#this use parameter expansion, if $1 undefined is Unknown error is substituted
	#$1 is the log message passed in
	log_msg "${1:-"Unknown Error"}"
	alert_me "${1:-"Unknown Error"}" 
	exit 1
}

#generate remedy tickets, send page
function alert_me
{
	#msg=$1
	servername=$(hostname)
	echo "$*" | mailx -s "${servername}: Error encountered, please see logs for details" ${support_email}
}

#get the current date
function get_current_time
{
	current_time=$(date +"%Y-%m-%d %H:%M:%S")	
}

function get_util_logheader
{
	get_current_time
	local function_name=$1
	local util_script=${BASH_SOURCE[0]}
	local process_id=$$
	[[ -n "${DELIMITER}" ]] || DELIMITER="~"
	util_log_header="${current_time}${DELIMITER}${process_id}${DELIMITER}${this_script}${DELIMITER}${function_name}${DELIMITER}"
}

#logs info and error messages
function log_msg
{
	get_util_logheader ${FUNCNAME[1]}
	local msg=$1
	local logmode=$2 
	
	#if message is for info and debug is on, then log, else no need to log information msgs
	#log all non info message
	if [[ ${logmode} -eq ${LOGGER_INFO} ]]; then
		if [[ ${debug_mode} -eq 1 ]]; then
			echo "${util_log_header}${msg}" >> ${logdir}/${logfile}
		fi
	else
		echo "${util_log_header}${msg}" >> ${logdir}/${logfile}
		echo "${util_log_header}${msg}" >> ${logdir}/${logfile_error}
	fi
}

# keep the last x number of log statements
function retain_lastx_log_size
{
	local mylogfile=$1
	shift
	local my_log_retention=$1

    tail -${my_log_retention} ${mylogfile} > ${mylogfile}.tmp
    cp ${mylogfile}.tmp ${mylogfile}
    rm ${mylogfile}.tmp
}

# verify unix shell that script supports
function verify_unix_shell
{
	local supported_unix=$1
	local osname=$(uname -s || return "error")
	if [[ ${osname} == "error" ]];then
		log_msg "${LINENO} ERROR Error checking for os version"
		return ${ERROR}
	fi
	
	if [[ ${osname} == ${supported_unix} ]];then
		return ${SUCCESS}
	else
		log_msg "${LINENO} WARNING program not tested for this OS. Detected OS=${osname}. Supported OS=${supported_os}"
		return ${WARNING}
	fi
}

#verify if the number is numeric
function is_numeric
{
	#this currently does not account for the floating numbers and 0
	expr $1 + 0 >/dev/null 2>&1 && return ${TRUE}
    return ${FALSE}
}

function isDirectory
{
	directory=$1
	#if not directory and not symbolic directory, then return success 
	if [[ -d "${directory}" && ! -L "${directory}" ]] ; then
		return ${SUCCESS}
	else
		return ${ERROR}
	fi
}

function isProd
{
	servername=$(hostname)
	#take substring of first 4 letters
	serverprefix=${servername:0:4}
	if [[ ${serverprefix} == "${prod_env_prefix:-oser}"  ]];then
		return ${TRUE}
	else
		return ${FALSE}
	fi
}

function isDev
{
	servername=$(hostname)
	#take substring of first 4 letters
	serverprefix=${servername:0:4}
	if [[ ${serverprefix} == "${dev_env_prefix:=tstr}"  ]];then
		return ${TRUE}
	else
		return ${FALSE}
	fi
}

function isCert
{
	servername=$(hostname)
	#take substring of first 4 letters
	serverprefix=${servername:0:4}
	if [[ ${serverprefix} == "${cert_evn_prefix:-cerl}"  ]];then
		return ${TRUE}
	else
		return ${FALSE}
	fi
}

function isFile
{
	local myfile=$1
	if [[ -f ${myfile} ]]; then
		return ${TRUE}
	else
		return ${FALSE}
	fi
}

function traps_signal
{
	#when program dies due to unexpected behavior, capture the signal and log it out
	echo "trapping signals"
}

function force_kill_process
{
	local processname=$1
	process_id_mon=$(ps -ef | grep ${processname} | grep -v 'grep\|view\|vi' | awk '{print $2}')
	if [[ ${process_id_mon} != "" ]]; then
		log_msg "Stopping monitor process which runs as process id: ${process_id_mon}" "1"
		kill -9 ${process_id_mon}
	fi
}

#check return code
function check_return_code
{
	return_code=$1
	msg=$2
	if [[ $return_code -ne 0 ]];then
		alert_me $msg
	fi
}

function increase_error_count
{
	log_msg "$$: increasing error count" "1"
	error_count=$(cat $logdir/$error_count_file)
	error_count=$(($error_count+1))	
	echo "$error_count" > $logdir/$error_count_file	
}

#exit the program program if error count exceeds the max
function check_error_exceeds_max
{
	error_count=$(cat ${logdir}/${error_count_file})
	#echo "Current error count is: $error_count"
	#exit program if no of errors is greater than a certain amount
	if [[ $error_count -gt $max_error ]];then
		alert_me "Number of errors exceed limit, program exiting..."
		log_msg " Number of errors exceed limit...max error is $max_error" "0"
		return ${TRUE}
	fi
	return ${FALSE}
}

#get ssh client and version
function get_ssh_client
{
	if [[ $(ssh -V 2>&1 | awk '{print $2}') = "OpenSSL" ]];then
		ssh_version="OpenSSL"
	elif [[ $(ssh --version 2>&1 | head -1 | awk '{print $3}') = "Tectia" ]];then
		ssh_version="Tectia"
	else
		ssh_version="Unknown"
	fi
}

#execute commands remotely
function exec_remote_cmd
{
	mycommand=$1
	exitcode=$2
	
	get_ssh_client
	if [[ $passwordless -eq 0 ]];then
		if [[ ${ssh_version} = "OpenSSL" ]];then
			password=$(cat $passdir/${passfile})
			myconn="sshpass -p '$password' ssh $username@$destserver"
		elif [[ ${ssh_version} = "Tectia" ]];then
			password=$(cat $passdir/${passfile})
			myconn="ssh $username@$destserver --password=$password"
		else
			myconn="ssh $username@$destserver"
		fi
	else
		myconn="ssh $username@$destserver"
	fi
	
	ssh_cmd="${myconn} ${mycommand}"
	return_value=$(eval $ssh_cmd)
	rc=$?
	
	if [[ ${rc} -ne 0 ]];then
		log_msg "Error executing remote command on $username at $destserver.  cmd: $mycommand with error code: ${rc}" "0"
		if [[ ${exitcode} -ne 0 ]];then
			alert_me "Error executing remote command on $username at $destserver. cmd: $mycommand"
			exit 1
		else
			return $rc
		fi
	fi
}


#check to see if required free disk space is sufficient 
function has_enough_space
{
	local required_space=$1
	shift
	local the_mount=$1
	#shift
	#local check_remote_server=$1
	
	if [[ ! -n $required_space ||  ! -n $the_mount ]];then
		log_msg "${LINENO} ERROR Incorrect amount of parameters passed in."
		return ${ERROR}
	else
		log_msg "${LINENO} INFO Checking required space: $required_space on mount: $the_mount" ${LOGGER_INFO}
	fi
	
	local len=${#required_space}
	local one=1 #space of the unit
	local lminus=$((len - one))
	
	#get the unit and number
	local inputunit=${required_space:$lminus:1}
	local inputnum=${required_space:0:$lminus}
	
	local mult=1000
	
	#figure out the unit and get the byte size
	if [[ $inputunit == "G" ]] || [[ $inputunit == "K" ]] || [[ $inputunit == "M" ]] || [[ $inputunit == "T" ]] ; then
		if [ $inputunit == "G" ] ; then #if space is in gigabytes
			local sq=$((mult*mult*mult))
			local fspace=$(echo "$inputnum * $sq" | bc)
		elif [ $inputunit == "K" ] ; then #if space is in kilobytes
			local fspace=$(echo "$inputnum * $mult" | bc)
		elif [ $inputunit == "M" ] ; then #if space is in megabytes
			local sq=$((mult*mult))
			local fspace=$(echo "$inputnum * $sq" | bc)
		elif [ ${inputunit} == "T" ]; then  #if space is in terabytes
			local sq=$((mult*mult*mult*mult))
			local fspace=$(echo "$inputnum * $sq" | bc)
		else
			error_exit "${LINENO} ERROR Unrecognized unit. Valid units are: T(tera), G(gig), M(meg), K(kilo)"
		fi
	elif [[ $inputunit == "0" ]] || [[ $inputunit == "1" ]] || [[ $inputunit == "2" ]] || [[ $inputunit == "3" ]] || [[ $inputunit == "4" ]] || [[ $inputunit == "5" ]] || [[ $inputunit == "6" ]] || [[ $inputunit == "7" ]] || [[ $inputunit == "8" ]] || [[ $inputunit == "9" ]] ; then
		local fspace=$required_space
	else
		log_msg "${LINENO} ERROR The input for required space is not valid. Input is $required_space"
		return ${ERROR}
	fi
	
	#Use of this code is to output/store the available space contained in a given mount
	#if [[ ${check_remote_server} -eq ${TRUE} ]]; then	
	#	log_msg "Checking remote server"
	#	local command="df -Ph $the_mount"
	#	exec_remote_cmd "${command}" "1"	
	#	local avail_space=`echo "${return_value}" | awk '{print $4}' | grep [0-9]`
	#else
	#if
		log_msg "${LINENO} Checking local server" ${LOGGER_INFO}
		#local avail_space=$(df -Ph ${the_mount} | tail -1 | awk '{print $4}' || echo "error")  #if any of the piped command failed, return an "error" message
		local avail_space=$(df -PH ${the_mount} | tail -1 | awk '{print $4}' || echo "error")  #if any of the piped command failed, return an "error" message
		if [[ ${avail_space} == "error" ]];then
			if [[ ${os_is_supported} -eq ${TRUE} ]];then
				cmd="df -Ph ${the_mount} | tail -1 | awk '{print $4}'"
			else
				cmd="df -PH ${the_mount} | tail -1 | awk '{print $4}'"
			fi
			log_msg "${LINENO} ERROR executing command to get available space. rc=$?. cmd=${cmd}"
			return ${ERROR}
		fi
	#fi
	 
	local length=${#avail_space} #measures the length of the given string
	local dminus=$((length-one)) #space of the number
	
	local unit=${avail_space:$dminus:1} #locates the location of the unit based on the space of the number
	local number=${avail_space:0:$dminus} #locates the number
	
	#series of if statements to determine the size of the file based on the Units K, M, G, T, or a normal byte
	#outputs the calculated size in bytes
	
	if [ $unit == "G" ] ; then #if space is in gigabytes
		local sq=$((mult*mult*mult))
		local space=$(echo "$number * $sq" | bc)
	elif [ $unit == "K" ] ; then #if space is in kilobytes
		local space=$(echo "$number * $mult" | bc)
	elif [ $unit == "M" ] ; then #if space is in megabytes
		local sq=$((mult*mult))
		local space=$(echo "$number * $sq" | bc)
	elif [ $unit == "T" ] ; then #if space is in terabytes
		local sq=$((mult*mult*mult*mult))
		local space=$(echo "$number * $sq" | bc)
	else #if space is in bytes
		local factor=1
		local space=$(echo "$number * $factor" | bc)
	fi
	
	if [ $(echo "$fspace > $space" | bc) -ne 0  ] ; then
		log_msg "${LINENO} ERROR Location does not have sufficient space. Need: $fspace Available: $space"
		alert_me "${LINENO} ERROR Location does not have enough sufficient. Need: $fspace Available: $space"
		return ${FALSE}
	else
		log_msg "Sufficient space available. Need: $fspace Available: $space" ${LOGGER_INFO}
		return ${TRUE}
	fi	
}

#get the time elapsed in minutes
function get_time_elapsed
{
	start_time=$1
	end_time=$2 #$SECONDS
	time_elapsed_in_sec=$(echo "($end_time-$start_time)"|bc -l)	
	time_elapsed_in_min=$(echo "($end_time-$start_time)/60"|bc -l|xargs printf "%.2f")
	time_elapsed_in_min_round_up=$(echo "($end_time-$start_time)/60"|bc -l|xargs printf "%1.f")	
}

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

	function init_unittest
	{
		#source util_func.cfg
		source misterclean.cfg
		logfile="unittest/misterclean_unittest.log"
		logfile_error="unittest/misterclean_error_unittest.log"
		unittest_file="unittest/unit_test.log"
		report_file_error="unittest/report_error.txt"
		report_file="unittest/baduser_unittest_report.txt"
		report_repeated_offenders="unittest/repeated_offenders.txt"
		local mydate=$(date)
		echo "******Starting unit tests at ${mydate}*******" >> ${unittest_file}
	}

	function assertEquals
	{
		msg=$1; shift
		expected=$1; shift
		actual=$1; shift
		/bin/echo -n "$msg: "
		if [ "$expected" != "$actual" ]; then
			echo "FAILED: EXPECTED=$expected ACTUAL=$actual"
		else
			echo "PASSED"
		fi
	}
	
	function local_space_not_enough_test
	{
		mount_space_needed="1T"
		mount_location="/Users"
		os_is_supported=${FALSE}
		has_enough_space "${mount_space_needed}" "${mount_location}"
		RC=$?
		assertEquals ">>>TEST local does not have enough space" ${FALSE} ${RC}
	}
	
	function max_error_count_test
	{
		echo "6" > ${logdir}/${error_count_file}
		max_error=5
		check_error_exceeds_max
		RC=$?
		assertEquals ">>>TEST error count exceeds max allowed" ${TRUE} ${RC} 
	}
	
	function logfile_size_cleanup_test
	{
		log_retention_line=2
		logfile="test.log"
		echo "log msg 1" > ${logdir}/${logfile}
		echo "log msg 2" >> ${logdir}/${logfile}
		echo "log msg 3" >> ${logdir}/${logfile}
		retain_lastx_log_size ${logdir}/${logfile} ${log_retention_line:-100000}
		log_size=$(cat ${logdir}/${logfile} | wc -l)
		assertEquals ">>>TEST retain log file size" 2 ${log_size}
	}
	
	function monitor_long_run_process_test
	{
		monitor_long_process=1
		process_max_time=1
		check_wait_time=1
		processtomonitor="longruntest.sh"
		mylogfile="longruntest.log"
		
		echo "echo \"testing long running process. sleeping at..\"" > ${processtomonitor}
		echo "date" >> ${processtomonitor}
		echo "sleep 125" >> ${processtomonitor}
		echo "echo \"waking up at...\"" >> ${processtomonitor}
		echo "date" >> ${processtomonitor}
		
		if [[ ${monitor_long_process} -eq 1 ]];then
			log_msg "Monitoring long running process" 
			nohup sh ${processtomonitor} &
			nohup sh mon_process_time.sh "$processtomonitor" "$process_max_time" "${check_wait_time}" "$support_email" "${logdir}/$mylogfile" &
			
			while [[ curr_count=$(ps -ef | grep $processtomonitor | grep -v "grep\|view\|vi\|mon_process_time.sh" | grep -c $processtomonitor) -ne 0 ]]
			do
				echo "Waiting for the last process to finish"
				sleep $sleeptime			
			done
		fi
		
		runlongcount=$(grep "running long" ${mylogfile} | wc -l)
		
		assertEquals ">>>TEST monitor long running process" 1 ${runlongcount}
		rm ${logdir}/${mylogfile}
		rm ${processtomonitor}
	}	
	
	function verify_unix_shell_test
	{
		#echo "Testing ${FUNCNAME[0]}" >> ${unittest_file}
		verify_unix_shell "Darwin"
		RC=$?
		assertEquals ">>>TEST verify unix shell" "${SUCCESS}" "${RC}"
	}

	function is_numeric_test
	{
		is_numeric "1"
		RC=$?
		assertEquals ">>>TEST is numeric" "${TRUE}" "${RC}"
	}

	function is_directory_test
	{
		local mydir="unittest_dir"
		mkdir -p ${mydir} || error_exit "Error running unit test to create directory" 
		isDirectory "${mydir}"
		RC=$?
		assertEquals ">>>TEST is directory" "${SUCCESS}" "${RC}"
		/bin/rm -r ${mydir} || error_exit "Error running unit test to delete directory" 
	}
	
	function is_prod_test 
	{
		isProd
		RC=$?
		assertEquals ">>>TEST is prod" "${TRUE}" "${RC}"
	}
	
	function is_cert_test 
	{
		isCert
		RC=$?
		assertEquals ">>>TEST is cert" "${TRUE}" "${RC}"
	}
	
	function is_dev_test 
	{
		dev_env_prefix="L-HO"
		isDev
		RC=$?
		assertEquals ">>>TEST is dev" "${TRUE}" "${RC}"
	}
	
	function is_file_test 
	{
		local myfile="unittest_file.txt"
		touch ${myfile} || error_exit "Error running unit test to create file" 
		isFile ${myfile}
		RC=$?
		assertEquals ">>>TEST is file" "${TRUE}" "${RC}"
		/bin/rm ${myfile} || error_exit "Error running unit test to remove file" 
	}

	function get_time_elapsed_test
	{
		local mystarttime=${SECONDS}
		sleep 5
		local mystoptime=${SECONDS}
		get_time_elapsed ${mystarttime} ${mystoptime}
		RC=${FALSE}				
		if [[ ${time_elapsed_in_sec} == "5" ]];then
			if [[ ${time_elapsed_in_min} == "0.08" ]];then
				if [[ ${time_elapsed_in_min_round_up} == "0" ]];then
					RC=${TRUE}
				fi
			fi
		fi

		assertEquals ">>>TEST get time elapsed" "${TRUE}" "${RC}"
	}

	init_unittest
	verify_unix_shell_test
	is_numeric_test
	is_directory_test
	is_prod_test
	is_cert_test
	is_dev_test
	is_file_test
	local_space_not_enough_test
	logfile_size_cleanup_test
	max_error_count_test
	get_time_elapsed_test
	#monitor_long_run_process_test
)
