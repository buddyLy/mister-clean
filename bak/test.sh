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
six
