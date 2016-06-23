#!/bin/bash

#initilize variable
function initialize
{
	progname=$(basename $0)
}

#continue to monitor monitor all the processes that's currently kicked off
function get_process_id
{
	#while [ 1 -eq 1 ]
	while [[ curr_count=$(ps -ef | grep $processname | grep -v 'grep\|view\|vi\|mon_process_time.sh' | grep -c $processname) -ne 0 ]]
	do
		for process_id in $(ps -ef | grep $processname | grep -v 'grep\|view\|vi\|mon_process_time.sh' | awk '{print $2}'); do
		#printf "calling elapsed with: %s\n" "$process_id"
		get_elapsed_time $process_id
	done
	wait_time=$(echo "$check_wait_time * 60" | bc)
	echo "$progname: Next check $check_wait_time min"
	sleep $wait_time
	done
}

#for the running time of each process
function get_elapsed_time
{
	process_id=$1
	#echo "process id in elapsed time: $process_id"
	for etime in $(ps -oetime $process_id | awk '{print $1}'); do
		#echo "word: $etime"
		if [[ $etime = "ELAPSED" ]];then
			continue
		fi
		#echo "etime: $etime"
		minute=$(echo $etime | awk -F':' '{print $1}')
		echo "process id $process_id has been running for $minute minutes"

		if [[ $minute -gt $maxruntime ]]; then
			echo "$progname: Process $process_id is running long. cmd: ps -ef | grep $processname | grep -v 'grep\|view\|vi\|mon_process_time.sh' | awk '{print $2}'"
			echo "$progname: Process $process_id is running long. Run time=$minute mins" | mailx -s "process $process_id is running long" $support_email
			echo "$progname: Process $process_id is running long. Been running over $minute minute" >> ${logfile}
		fi
	done
}

#start the main script
function start_script
{
	initialize
	get_process_id
}

#---main----
processname=$1
shift
maxruntime=$1
shift
check_wait_time=$1
shift
support_email=$1
shift
logfile=$1

start_script
