function one
{
	set -o pipefail
	local bad_user_list=$(du -s /Users/lcle 2>/dev/null| awk 'BEGIN{} {if($1>300000) {$1=$1/(1024*1024);print $0}}' 2>/dev/null|| echo "errors")

	local cmd="find ${user_basedir}/${user} -size +${max_file_size} -atime +${retention_period}d -type f -print0 | xargs -0 ls"
	list_of_bad_files=$(${cmd} || echo "error")

	if [[ ${bad_user_list} == "errors" ]];then
		echo "error with user lcle"
	else
		echo "$bad_user_list"
	fi
}

function two
{
#myarray=(one two three)
myarray2=()
myarray=()
myarray2=(b c d)
echo "lenth: ${#myarray[@]}"
echo "lenth2: ${#myarray2[@]}"
for x in ${myarray[@]}; do
	echo $x
done
}
function three
{
echo "executor: ${executor}"
}

function four
{
	myarray1=${!1}
	myarray2=${!2}
}

function three
{
	array1=(a b c)	
	array2=([ly]="file1 file2 file3" [emma]="file1 file2")
	declare -a array3
	array3=([foo]=bar [zoom]=fast)
	#four array1[@] array2[@]
	for i in ${!array3[*]};do
		echo $i
	done
}

generate_report()
{
	array_size=$1
	for (( j=0; j<$array_size; j++ ));do
		shift
		local column=$1
		report="${report}${column}\t"
	done
#	column1=$1
#	shift
#	column2="$1"
#	shift
#	column3=$1
	
	report="${report}\n"
	#report="${report}${column1}\t${column2}\t${column3}\n"
	echo -e "report so far: \n$report"
	#printf "%s" "$report"
}

function three
{
	header="email,name,size"
	IFS="," && array1=(${header})
	echo "size array: ${#array1[*]}"
	
	email="ly@yahoo.com"
	name="lcle"
	size="32Gb"
	local i
	for (( i = 0; i<2; i++ )); do
		#echo "column 1: ${!array1[0]}"
		#echo "column 2: ${!array1[1]}"
		#echo "column 3: ${!array1[2]}"
		generate_report "${#array1[*]}" "${!array1[0]}" "${!array1[1]}" "${!array1[2]}"
		email="ly2@yahoo.com"
		name="lcle2"
		size="33Gb"
	done
		email="ly3@yahoo.com"
		name="lcle3"
		size="34Gb"
		generate_report "${#array1[*]}" "${!array1[0]}" "${!array1[1]}" "${!array1[2]}"
}

function four
{
	for x in $(ls -F /Users/lcle/tmp/users | grep "/" || echo "error")
	do
		echo "value: $x"
	done
}

function five
{
FILES=(
  "2011-09-04 21.43.02.jpg"
  "2011-09-05 10.23.14.jpg"
  "2011-09-09 12.31.16.jpg"
  "2011-09-11 08.43.12.jpg"
)

for f in "${FILES[@]}"
do
  echo "file: $f"
done
}


function six
{
	results=$(find /Users/lcle/tmp/users/user2/ -size +16M -atime +5d -type f -print0 | xargs -0 ls)
	#IFS=$'\n'
	for x in ${results}; do
		echo "x is: $x"
	done
	#unset IFS
}

function seven
{
	#for x in $(find /Users/lcle/tmp/users/user2/ -size +16M -atime +5d -type f -print0 | xargs -0 ls); do
	#find "/Users/lcle/tmp/users/user2/" -size +16M -atime +5d -type f |  while read f
	#find /Users/lcle/tmp/users/user2/ -size +16M -atime +5d -type f -print0 | xargs -0 ls | while read f
	find /Users/lcle/tmp/users/user2 -type f -print0 | xargs -0 ls | while read f
	#for f in $(find /Users/lcle/tmp/users/user2/ -size +16M -atime +5d -type f -print0 | xargs -0 ls | read)
	do
		echo "f is: $f"
	done
}

function eigth
{
	du -s /Users/lcle/tmp/users/user2/ | awk -v limit=300000 'BEGIN{} {if($1>limits) {$1=$1/(1024*1024);print $0}}'
}

function nine
{
	one=1	
	if ((1>one));then
		echo "true"
	else
		echo "false"
	fi
}

function ten
{
	echo "1324" | awk -v limit=172791 'BEGIN{} {if(172792>limit) {print "true"}}'
}

function eleven
{
	#date 
	#date --date="7 days ago" +%H%M-%d%m%Y #gnu date
	dateformat="+%m-%d-%Y"
	days=7
	daysago=$(date -j -v-${days}d ${dateformat})
	today=$(date ${dateformat})
	echo "today: $today"
	echo "daysgo: $daysago"
}

function twelve
{
	dateformat="+%m-%d-%y"
	days=3
	daysago=$(date -j -v-${days}d ${dateformat})
	today=$(date ${dateformat})
	echo "today: $today"
	echo "daysgo: $daysago"
	local founddate="false"
	IFS=$'\n' read -d '' -r -a lines < ./badusers.txt
	for line in ${lines[*]}; do
		local parsedwords=($(echo ${line} | tr '|' "\n"))	
		local thedate=${parsedwords[0]}
		local theuser=${parsedwords[1]}
		if [[ $thedate == "date" ]];then
			continue
		fi
		echo "line: $line ~ date: $thedate theuser: $theuser"
		#if (( daysago > thedate )); then
		if [[ $founddate == "false" ]];then
			if [[ $daysago != $thedate ]]; then
				continue
			else
				founddate="true"
			fi
		fi
		daysarray+=("$thedate|$theuser")
	done
	echo "captured:\n ${daysarray[*]}"
	unset IFS
}

function thirteen
{
	line1="a|b|c"
	#IFS='|' read -d '|' -r -a word <<<< $line1
	echo ${word[2]}
}

function fourteen
{
	t="one,two,three"
	a=($(echo $t | tr ',' "\n"))
	echo "value: ${a[2]}"
	for x in ${a[*]};do
		echo "ind: $x"
	done
}

function fifteen
{
	badusers=()
	local index=0
	array1=("11-01-15|user1|1G" "11-02-15||user2|1G" "11-03-15||user3|4G" "11-04-15|user1|6M" "11-05-15|user3|8T") 

	alreadycompared=()
	local compared="false"
	echo "array at: ${array1[1]}"
	for x in ${array1[*]}; do
		local usercount=0
		echo "usercount: $usercount"
		local parsedwords=($(echo ${x} | tr '|' "\n"))	
		local thedate=${parsedwords[0]}
		local theuser=${parsedwords[1]}
		
		#check to see if it's already been compared
		for z in ${alreadycompared[*]}; do
			if [[ $theuser == $z ]];then
				compared="true";
			fi	
		done

		if [[ $compared == "true" ]];then
			continue
		fi

		alreadycompared+=("$theuser")
		#echo "user: ${parsedword[1]}"
		
		#loop thru same array and count up the nbr of times on the bad list
		for y in ${array1[*]};do
			local parsedwords2=($(echo ${y} | tr '|' "\n"))	
			local thedate2=${parsedwords[0]}
			local theuser2=${parsedwords2[1]}
			if [[ $theuser == $theuser2 ]];then
				(( usercount++ ))				
			fi
		done

		local offendeduser="${theuser}|$usercount\n"
		repeatedoffenders+=("$offendeduser") 
#		for y in ${badusers[*]}; do
#			if [[ ${parsedword} != ${y} ]]; then
#				badusers[index] = ${parsedword}	
#				(( index ++ ))
#				echo "index at: $index"
#			fi
#		done
	done
	#echo "here are the bad users: ${badusers[*]}"
	echo "here are the repated offenders:\n ${repeatedoffenders[*]}"
}

function sixteen
{
	local array1=(1 2 3 4 5)
	local index=0
	for i in ${array1[*]};do
		if [[ $i -eq 3 ]]; then
			continue
		fi
		(( index++ ))
		echo "index: $index"
		echo "value: $i"
	done
	
}	

function seventeen
{
	bypass_warning=1
	false || if (( !bypass_warning )); then echo "exiting"; fi
}

function eithteen
{
	echo "lcle: [[ "${BASH_SOURCE[0]}" == "${0}" ]]"
}

function nineteen
{
	echo "something"
	tr a-z A-Z <<< "one"
#	tr a-z A-Z <<< '
#	 one
#	  two three
#	  ' 
}

function get_time_elapsed
{
	start_time=$1
	end_time=$2 #$SECONDS
	time_elapsed_in_sec=$(echo "($end_time-$start_time)"|bc -l)	
	time_elapsed_in_min=$(echo "($end_time-$start_time)/60"|bc -l|xargs printf "%.2f")
	time_elapsed_in_min_round_up=$(echo "($end_time-$start_time)/60"|bc -l|xargs printf "%1.f")	
	echo "time_elapsed_in_sec $time_elapsed_in_sec"
	echo "time_elapsed_in_min $time_elapsed_in_min"
	echo "time_elapsed_in_min_round_up $time_elapsed_in_min_round_up"
}

function twenty
{
	start=${SECONDS}
	sleep 5
	end=${SECONDS}
	get_time_elapsed $start $end
}

function twentyone
{
	[[ 0 -eq 1 ]] && echo "true" || echo "false"
}
twentyone
