#!/bin/bash
#launch.sh

function print_help {
cat -v << EOF
USAGE: "launch.sh -c <command> [OPTIONS]"

-c  --cmd COMMAND	: Submit a single command to launchpad.
-l  --list <file> 	: Multiple command submission from <file>. Requires the Multi-Job.sh script.

-m  --mail <address>	: E-mail the user at the specified address when a job starts and finishes.
-s  --server <cluster>	: Remote compute cluster server. Default is launchpad."
-r  --source		: (dev/stable/*) FreeSurfer set up file that you wish to source in launchpad.
-N  --nodes <N>		: Number of nodes demanded = N
-p  --path <path>	: Location of the Multi-Job.sh helper script.
-h  --help		: Print this help.
-u  --usage		: More detailed usage information for launch.sh script

--user <username>	: NMR user name.

EOF
}

function usage {

print_help
cat -v << EOF
This script will submit jobs for processing to the launchpad cluster. Jobs can be submitted either one at a
time or in bunches (see flags below for more detail). Script requires valid nmr user name and password to
log onto launchpad. The script will prompt user for a password if it is not specified in command line
(therefore make sure its coded in with the password flag if this script is being used in another script).
The default operation of the script is to submit the jobs to launch pad in the terminal window from which
launch.sh is called.

	NOTE: You must either edit the defaults in this script before use in order to source correct FreeSurfer
	version and locate Multi-Job.sh script or you must explicitly specify them using the -source and
	-helper_path flags!!


IMPORTANT TERMINAL PROFILE INFORMATION:
For launch.sh to run correctly two terminal profiles must exist on your computer: Hold and NoHold.
To make new terminal profiles open a terminal window and click on the edit drop down menu, and select
Profiles... Click on the "New" button to add a profile, name the profile "Hold" and click create."
In the Editing Profile 'Hold' window, select the "Title and Command" tab. For the "When command"
exits drop down menu, select Hold the terminal open".  Make another new profile, this time naming it"
NoHold.  On the "Title and Command" tab of the "Editing Profile 'NoHold'" window select"
Exit the terminal for the "When command exits" drop down menu."

These two profiles are required for correct operation of the script in a new terminal window!


EXAMPLES:

To launch a single recon-all command on launch pad in the current terminal window, first source correct
FreeSurfer enviornment and set subject's directory.  Run the following command:
	launch.sh -user_name <your_username> -cmd "recon-all -subjid <subject_ID> -all"
This is the equivilent of logging into launchpad and running:
pbsubmit -c recon-all -subjid <subject_ID> -all"


To run the submission in a new terminal window use:
	launch.sh -user_name <you_username> -cmd  recon-all -subjid <subject_ID> -all" -new_term"
This will submit the same job to launchpad in a new terminal window, allowing you to continue working in
the current window, or a script to continue running in the current terminal.


To run more than one command line two other things are required:
1. Text file with commands listed
2. Multi-Job.sh script
This script must be edited in order to pass the use the correct location of Multi-Job.sh
The text file must contain the commands list out, one per line without space in between:
COMMAND 1
COMMAND 2
COMMAND 3
Call launch.sh using the -cmd_list flag and the location path of the text file:
	launch.sh -user_name <you_username> -cmd_list <Path_to_text_file>
The -new_term flags may also be used if desired.


To use launch.sh in a script, you must pass it your password explicitly using the -password flag:
	launch.sh -user_name <you_username> -password <password> -cmd_list <Path_to_text_file>
If you do not the script will stop and wait for your password before continuing, the above line will
allow a script to call launch.sh without supervision.
EOF
}

_TestSSH() {
local user=${1}
local host=${2}
local timeout=${3}

#echo "ssh -q -q -o \"BatchMode=yes\" -o \"ConnectTimeout ${timeout}\" ${user}@${host}"
ssh -q -q -o "BatchMode=yes" -o "ConnectTimeout ${timeout}" ${user}@${host} : && exit || exit $?

}

run_expect () {
EXPECT_COMMAND="expect"
if [[ $MULTI -eq 1 ]]; then
	RUN_CMD="send \"$helper_path/Multi-Job.sh $command_list $nodec $wait $delay\r\"; \
		 expect -timeout 3600 \"COMPLETE\";"
else
	RUN_CMD="send \"pbsubmit -c \'$command\' $nodec $seychelles_cmd $mail_command\r\"; \
		 expect -timeout 360 \"$server.nmr.mgh.harvard.edu\";"
fi

if [[ $SSHTEST -eq 0 ]]; then
	AUTH_CMD="sleep 0.5;"
else
	if [[ -z $password ]]; then
	   printf "%-29s" "Please enter your password:"
	   stty -echo
	   read password
	   stty echo
	   echo ""
	fi 
	AUTH_CMD="expect \"password:\"; send \"$password\r\";" 
fi

$EXPECT_COMMAND << EOF
spawn ssh $user_name@$server;
$AUTH_CMD
expect "%> "; sleep 0.5;
send "source $source\r";
$RUN_CMD
EOF
}

run_ssh () {
if [[ $MULTI -eq 1 ]]; then
	RUN_CMD="$helper_path/Multi-Job.sh $command_list $nodec $wait $delay"
else
	RUN_CMD="pbsubmit -c '$command' $nodec $seychelles_cmd $mail_command"
fi

ssh -t -q $user_name@$server << EOF
source $source
$RUN_CMD
EOF
}

#############################################################################################################################
##########################################             START SCRIPT         #################################################

#error exit codes:
NO_CMD=20
NO_COMMAND_LIST=22

nodes=1
wait=""
source=/autofs/space/eesmith_001/users/dierksen/Petichial/SetUpFreeSurferV4.bash
helper_path=/autofs/space/eesmith_001/users/dierksen/Petichial/scripts
user_name="$USER"
server="launchpad"

MAIL=0
MULTI=0
NEWTERM=0
KEYAUTH=1
EXPECT=0

while [ $# != 0 ];
do
	flag="$1"
	case "$flag" in
		-c|--cmd)
			command=$2
			shift
			;;
		-l|--list)
			command_list=$2
			MULTI=1
			shift
			;;
		--user)
			user_name=$2
			shift
			;;
		-r|--source)
			source=$2
			shift
			;;
		-p|--path)
			helper_path=$2
			shift
			;;
		-m|--mail)
			MAIL=1
			address=$2
			shift
			;;
		-N|--nodes)
			nodes=$2
			shift
			;;
		-s|--server)
			server=$2
			shift
			;;
		-wait)
			wait="-wait"
			;;
		-e|--expect)
			EXPECT=1
			;;
		-d)
			DELAY=$2
			shift
			;;
		-h|-help|--h|--help)
			print_help && exit
			;;
		-u|--u|-usage)
			usage && exit
			;;
		*)
			echo "Invalid flag:"
			echo $flag
			print_help && exit
			;;
	esac
	shift
done

#test SSH connection
TIMEOUT=5
( _TestSSH $user_name $server $TIMEOUT )
SSHTEST=$?

#[ $SSHTEST ] && echo "using SSH key authentication." || echo "using expect."
[ $SSHTEST ] && KEYAUTH=1 || KEYAUTH=0

if [[ $SSHTEST -eq 0 ]] && [[ $KEYAUTH -eq 1 ]] && [[ $EXPECT -eq 0 ]]; then
	echo "using ssh key authentication..."
	METHOD="ssh"
else
	echo "using expect..."
	METHOD="expect"
fi

#check for command existence and exit if none
if [[ -z "$command" && -z "$command_list" ]]; then
	echo "Please specify a command to run."
	print_help
	exit $NO_COMMAND
fi


#Default to USER's email address at NMR
if [[ -z $address ]]; then
	address="${USER}@nmr.mgh.harvard.edu"
fi

#Mail command
if   [[ $MAIL == 1 ]]; then
echo "MAIL: on finish to $address."
   if   [[ $MULTI -eq 1 ]]; then
	command_list="$command_list -m $address"
   else
	mail_command="-m $address"
   fi
fi

#Source shortcuts
case "$source" in
	stable)	source=/autofs/cluster/ichresearch/Petechial/SetUpFreeSurferV5.bash	;;
	dev)		source=/autofs/cluster/ichresearch/Petechial/SetUpFreeSurferDEV.bash	;;
	*)		source="$source"										;;
esac

#Number of nodes (if needed)
if [[ $nodes -gt 1 ]]; then
	nodec=" -n $nodes"
fi

#Specific options for seychelles cluster
seychelles_cmd=""
if [[ $server == "seychelles" ]]; then
	seychelles_cmd="-l nodes=1:bigmem"
	nodec=""
elif [[ $server == "seychelles" && $MULTI -eq 1 ]]; then
	command_list="$command_list -s seychelles"
fi

#check/fix appropriate paths for source/command_list
[[ -e "$PWD/$command_list" ]] && command_list="$PWD/$command_list"
[[ -e "$PWD/$source" ]] && source="$PWD/$source"

#verify command file existence and set delay
if [[ $MULTI -eq 1 ]]; then
   if [[ ! -e $command_list ]]; then
   	echo "Command file: $command_list not found."
   	exit $NO_COMMAND_FILE
   fi
   [ -n "$DELAY" ] && delay="-d $DELAY"
fi

case "$METHOD" in
	expect)	run_expect	;;
	ssh)		run_ssh		;;
esac

