#!/bin/bash
# Boostrap script for new controller node
# sudo@redhat.com, 2022
# This script requires the /root/.bootstrap.cfg to be setup, see bootstrap.cfg-example for what needs to be defined
 

if [ ! -f /root/.bootstrap.cfg ]; then
        echo "Error: No configuration file found."
        echo "Copy bootstrap.sh-example to /root/.bootstrap.cfg and fill the required values."
        exit 1
else
        . /root/.bootstrap.cfg
fi

echo "Running Ansible Automation Platform bootstrap script."

# Install the CLI which we'll use to create the initial resources needed to start configuring everything from BitBucket
if ! rpm -q automation-controller-cli >/dev/null; then
        dnf install -y automation-controller-cli
fi

if ! grep "TOKEN" /root/.bootstrap.cfg >/dev/null; then
        echo "Did not find a configured token, creating one."
        echo "Creating login token:"
	TOKEN=$(awx login -k --conf.useradmin admin --conf.password $ADMINPASS --conf.host https://$(hostname)|grep token|awk '{ print $2 }'|sed 's/"//g')
        echo "TOKEN=$TOKEN" >>~/.bootstrap.cfg
fi

if [ "$GIT_AUTH_ENABLED" == "true" ]; then
	echo "Checking for credentials for BitBucket integration, creating credentials if not created already"
	 if ! awx -k --conf.token=$TOKEN credentials list|grep "$GITCREDNAME" >/dev/null; then
        	awx -k --conf.token $TOKEN credentials create --credential_type 'Source Control' --name "$GITCREDNAME" --user admin --inputs '{ "username": "'"$GITCREDUSER"'", "password": "'"$GITCREDPASS"'" }'
	fi
fi

echo "Create Red Hat Cloud/Private Automation hub integration"
awx -k --conf.token $TOKEN credentials create --credential_type 'Ansible Galaxy/Automation Hub API Token' --name "Red Hat Cloud Automation Hub" --organization Default --inputs '{ "url": "'"$GALAXY_SERVER_URL"'", "auth_url": "'"$AUTH_SERVER_URL"'", "token": "'"$API_TOKEN"'" }'

echo "Fetch Automation hub credential id"
HUB_CREDENTIAL_ID=$(awx -k --conf.token $TOKEN credentials get "Red Hat Cloud Automation Hub"|grep id|head -1|cut -d: -f2|sed -e 's/ //g' -e 's/,//g')

echo "Associate credential with Default organization"
awx -k --conf.token $TOKEN organizations associate --galaxy_credential $HUB_CREDENTIAL_ID 1

echo "Checking if Controller configuration project has been created, creating it if not there."
if ! awx -k --conf.token=$TOKEN projects list|grep "controller_configuration" >/dev/null; then
	if [ "$GIT_AUTH_ENABLED" == "true" ]; then
        	awx -k --conf.token=$TOKEN projects create --name "controller_configuration" --scm_type git --scm_url=$SCM_URL --scm_branch $SCM_BRANCH --scm_clean true --scm_delete_on_update true --credential $GITCREDNAME --organization 1 --scm_update_on_launch true
	else
		awx -k --conf.token=$TOKEN projects create --name "controller_configuration" --scm_type git --scm_url=$SCM_URL --scm_branch $SCM_BRANCH --scm_clean true --scm_delete_on_update true --organization 1 --scm_update_on_launch true
	fi
fi

 
if [ "$LDAP_ENABLED" == "true" ]; then
	echo "Configuring ldap integration"
	awx -k --conf.token=$TOKEN settings modify "AUTH_LDAP_SERVER_URI" "ldap://oneadr.net:3268"
	awx -k --conf.token=$TOKEN settings modify "AUTH_LDAP_BIND_DN" "CN=$LDAPUSER,OU=Service-Accounts,OU=Accounts,OU=_CORP,DC=oneadr,DC=net"
	awx -k --conf.token=$TOKEN settings modify "AUTH_LDAP_BIND_PASSWORD" "$LDAPPASS"
	awx -k --conf.token=$TOKEN settings modify "AUTH_LDAP_GROUP_TYPE" "ActiveDirectoryGroupType"
	awx -k --conf.token=$TOKEN settings modify  "AUTH_LDAP_USER_SEARCH" '[["OU=Users,OU=Accounts,OU=_CORP,dc=oneadr,dc=net","SCOPE_SUBTREE","(sAMAccountName=%(user)s)"],["OU=Vendors,OU=Accounts,OU=_CORP,dc=oneadr,dc=net","SCOPE_SUBTREE","(sAMAccountName=%(user)s)"]]'
	awx -k --conf.token=$TOKEN settings modify  "AUTH_LDAP_GROUP_SEARCH" '["OU=Groups,OU=_CORP,DC=oneadr,DC=net","SCOPE_SUBTREE","(objectClass=group)"]'
	awx -k --conf.token=$TOKEN settings modify  "AUTH_LDAP_USER_ATTR_MAP" '{"first_name": "givenName","last_name": "sn","email": "mail"}'
fi

echo "Fetching Controller configuration project ID"
PROJECTID=$(awx -k --conf.token=$TOKEN project list|grep "controller_configuration"|grep "local_path"|cut -d: -f2|sed -e 's/"//g' -e 's/__.*//g' -e 's/ _//g')

echo "Creating Controller configuration vault."
awx -k --conf.token $TOKEN credentials create --credential_type 'Vault' --name "$VAULTNAME" --organization Default --inputs '{ "vault_password": "'"$VAULTPASS"'" }'

VAULTID=$( awx -k --conf.token $TOKEN credentials get "$VAULTNAME"|grep id|head -1|cut -d: -f2|sed -e 's/ //g' -e 's/,//g')

echo "Waiting for project to sync"
sleep 15
echo "Creating Controller configuration job template"
awx -k --conf.token=$TOKEN job_templates create --name "Controller Synchronization" --organization 1 --project $PROJECTID --playbook "aap-synchronization.yml" --description "Job which configures the Controller cluster, stored at $SCM_URL" --inventory 1 --limit localhost --extra_vars "{ load_balancer_fqdn: $LOAD_BALANCER_FQDN, controller_hostname: $(hostname -f), controller_fqdn: $(hostname -f) }"

TEMPLATEID=$(awx -k  --conf.token=$TOKEN job_template get "Controller Synchronization"|grep id|head -1|cut -d: -f2|sed -e 's/ //g' -e 's/,//g')

echo "Associating vault to job template"
awx -k  --conf.token=$TOKEN job_template associate $TEMPLATEID --credential $VAULTID

if echo $1|grep -i "delete" >/dev/null; then
	if [ -f /root/.bootstrap.cfg ]; then
        	echo "Cleaning up bootstrap.cfg file."
  	        rm -f /root/.bootstrap.cfg
        	if [ "$?" -ne 0 ]; then
            	   echo "ERROR: Could not clean up /root/.bootstrap.cfg. Do so manually."
      	  	fi
	fi
fi

