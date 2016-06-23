#!/bin/bash
function turn_on_trace_mode
{
	#turning on tracing mode. 
	#turn on trace mode only when trace mode option is true 
	[[ $trace_mode -eq 1 ]] && set -x
	PS4='$LINENO: '
	exec 5> debug_output.txt
	BASH_XTRACEFD="5"
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
    tail -${log_retention} ${logdir}/${logfile} > ${logdir}/${logfile}.tmp
    cp ${logdir}/${logfile}.tmp ${logdir}/${logfile}
    rm ${logdir}/${logfile}.tmp
}

# verify unix shell that script supports
function verify_unix_shell
{
	local supported_unix=$1
	echo "checking unix shell version"
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


#purge process
function cleanup_after_yourself 
{
	#do purge process here
	echo "purge process"
}

#create directory if doesn't exist
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

function isFile
{
	if [[ -f ${file} ]]; then
		return ${SUCCESS}
	else
		return ${ERROR}
	fi
}

function traps_signal
{
	#when program dies due to unexpected behavior, capture the signal and log it out
	echo "trapping signals"
}

#do final cleanup
function cleanup
{
	if [[ $monitor_long_process -eq ${TRUE} ]];then
		process_id_mon=$(ps -ef | grep mon_process_time.sh | grep -v 'grep\|view\|vi' | awk '{print $2}')
	
		if [[ ${process_id_mon} != "" ]]; then
			log_msg "Stopping monitor process which runs as process id: $process_id_mon" "1"
			kill -9 $process_id_mon
		fi
	fi 
	retain_lastx_log_size
 	cleanup_after_yourself	
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
	error_count=$(cat ${logdir}/$error_count_file)
	echo "Current error count is: $error_count"
	#exit program if no of errors is greater than a certain amount
	if [[ $error_count -gt $max_error ]];then
		alert_me "Number of errors exceed limit, program exiting..."
		log_msg " Number of errors exceed limit...max error is $max_error" "0"
		return ${TRUE}
		#exit 1
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
	shift
	local check_remote_server=$1
	
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
	if [[ ${check_remote_server} -eq ${TRUE} ]]; then	
		log_msg "Checking remote server"
		local command="df -Ph $the_mount"
		exec_remote_cmd "${command}" "1"	
		local avail_space=`echo "${return_value}" | awk '{print $4}' | grep [0-9]`
	else
		log_msg "${LINENO} Checking local server" ${LOGGER_INFO}
		local avail_space=$(df -Ph ${the_mount} | tail -1 | awk '{print $4}' || echo "error")  #if any of the piped command failed, return an "error" message
		if [[ ${avail_space} == "error" ]];then
			cmd="df -Ph ${the_mount} | tail -1 | awk '{print $4}'"
			log_msg "${LINENO} ERROR executing command to get available space. rc=$?. cmd=${cmd}"
			return ${ERROR}
		fi
	fi
	 
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
		log_msg "${LINENO} ERROR Location does not have enough available space to transfer file. Need: $fspace Available: $space"
		return ${ERROR}
	else
		log_msg "You have enough space to transfer. Need: $fspace Available: $space" ${LOGGER_INFO}
		return ${SUCCESS}
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
	mycfgfile="/my/config/file/program_config.cfg"
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
		source ${mycfgfile}
		has_enough_space "1T" "/u" "1"
		assertEquals ">>>TEST local doesn't have enough space" ${FALSE} $?
	}
	
	function max_error_count_test
	{
		source ${mycfgfile}
		echo 6 > ${logdir}/$error_count_file
		max_error=5
		check_error_exceeds_max
		assertEquals ">>>TEST error count exceeds max allowed" ${TRUE} $?
	}
	
	function logfile_size_cleanup_test
	{
		source ${mycfgfile}
		log_retention=2
		logfile="test.log"
		echo "log msg 1" > ${logdir}/${logfile}
		echo "log msg 2" >> ${logdir}/${logfile}
		echo "log msg 3" >> ${logdir}/${logfile}
		retain_lastx_log_size
		log_size=$(cat ${logdir}/${logfile} | wc -l)
		assertEquals ">>>TEST retain log file size" 2 ${log_size}
	}
	
	function monitor_long_run_process_test
	{
		source ${mycfgfile}
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
		
		if [[ $monitor_long_process -eq 1 ]];then
			log_msg "Monitoring long running process" "1"
			nohup sh ${processtomonitor} &
			nohup sh mon_process_time.sh "$processtomonitor" "$process_max_time" "${check_wait_time}" "$support_email" "${logdir}/$mylogfile" &
			
			while [[ curr_count=$(ps -ef | grep $processtomonitor | grep -v 'grep\|view\|vi\|mon_process_time.sh' | grep -c $processtomonitor) -ne 0 ]]
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
	
	function variable_initialize_test
	{
		source ${mycfgfile}
		initialize_loggers
		success=1
		[[ -e ${passdir}/${passfile} ]] || success=0
		[[ -e ${logdir}/${logfile} ]] || success=0
		[[ -e ${logdir}/${status_file} ]] || success=0
		[[ -e ${logdir}/${total_sent_status} ]] || success=0
		[[ -e ${logdir}/${error_count_file} ]] || success=0
		
		assertEquals ">>>TEST initialize variables" 1 $success
	}
	
	#Test calls
	initialize_loggers_test
	local_space_not_enough_test
	logfile_size_cleanup_test
	max_error_count_test
	monitor_long_run_process_test
)
