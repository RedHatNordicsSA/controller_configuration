#!/bin/bash
# Script which triggers sync of job templates from outside of AAP
# Magnus Glantz, sudo@redhat.com, 2022

# Source token from .token.cfg file
# If it doesn't exist, create file containing: TOKEN="your token"
. ~/.token.cfg

if ! rpm -qa|grep jq >/dev/null
then
	echo "Error: You need to run: dnf install jq"
	exit 1
fi

# Number of job id's we will iterate through, adjust as required
for i in {1..200}
do
	RESULT=""
	RESULT=$(awx -k --conf.token $TOKEN job_templates get $i)
	if [ "$?" -eq 0 ]
	then
		JOBID=$(echo $RESULT|jq .id)
		JOBNAME=$(echo $RESULT|jq .name)
		if echo $JOBNAME|grep -i "Controller Synchronization" >/dev/null
		then
			awx -k --conf.token $TOKEN job_templates launch $JOBID --wait >/dev/null
			if [ "$?" -eq 0 ]; then
				echo "Ran: $JOBNAME"
			fi
		fi
		if echo $JOBNAME|grep -i "Customer synchronization" >/dev/null
		then
			awx -k --conf.token $TOKEN job_templates launch $JOBID >/dev/null
                        if [ "$?" -eq 0 ]; then
                                echo "Ran: $JOBNAME"
			fi
		fi
	fi
done

