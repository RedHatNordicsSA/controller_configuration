#!/bin/bash
# Script which triggers sync of job templates from outside of AAP
# Can be used in case of failover between sites (triggered by monitoring solution) or in case of disaster recovery
# Or in case you cannot use webhooks to trigger syncs
#
# For this to run, create a file called ~/.customers.cfg which lists the unique identifiers of your customers sync jobs
# Example:
# CustomerX
# CustomerY
# Magnus Glantz, sudo@redhat.com, 2022

# Source token from .token.cfg file
# If it doesn't exist, create file containing: TOKEN="your token"
. ~/.token.cfg

echo "Running main sync job"
awx -k --conf.token $TOKEN job_templates launch "Controller Synchronization" --wait >/dev/null 2>&1
if [ "$?" -eq 0 ]
then
	echo "Main sync job ran successfully, will now continue to run customer sync jobs"
fi

# Run all the customer sync jobs asynchroniously, at the same time.
for customer in $(cat ~/.customers.cfg|grep -v "#")
do
	echo "Customer synchronization - Customer $customer"
	awx -k --conf.token $TOKEN job_templates launch "Customer synchronization - Customer $customer"
        if [ "$?" -eq 0 ]; then
        	echo "Launched job template: Customer synchronization - Customer $customer"
	fi
done

