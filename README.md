# controller_configuration
Example architecture for a highly available Ansible Automation Platform controller setup which provides automation as a service.

If you are not planning of providing automation as a service for others, ignore the https://github.com/RedHatNordicsSA/customer* repositories.

* Almost completely based on https://github.com/redhat-cop/controller_configuration

![Alt text](img/overview-aap.png?raw=true "Overview")

Consists of load balancer in front of two separate AAP clusters, both which are online all the time. One cluster is active, and provides an interface for users, API calls and runs scheduled tasks. The other cluser is standing by to receive traffic from the load balancer in case of failure or if we are doing a green-blue type upgrade.

## Key advantage
* Supports full disaster recovery and 99,999% high availability. Convergence time is very short (1-3 seconds). Time passed from going down to service coming up again can in this way be as little as can be provided by the load balancer. That makes this a good fit for usecases when automation must not fail.
* Allows for blue-green type upgrades, also between major releases (AAP 1.2 -> 2.1), this further reduces risk and increases availability.
* The simple nature of the setup makes it robust and easier to manage than setups which depends on database replication or other infrastructure based HA functions.

## Key consideration
* Requires web hook integration from version control system or CI-engine which monitors repos to controller/customer synchronization job templates.
* Users need to reside in LDAP for this setup to work at scale. Map (also customers) users to teams and organization using LDAP mapping described here: https://docs.ansible.com/automation-controller/latest/html/administration/ldap_auth.html#ldap-organization-and-team-mapping 
* Users should _not_ be provided write access in AAP, all changes should be done via git using an integration user. Otherwise the two clusters _will_ at some point differ and HA is no longer provided for all automation. It's OK if some people maintaining the platform has write access for debug purposes.
* You will need to keep yourself in sync with https://github.com/redhat-cop/controller_configuration, this is currently not a difficult task, but that may not be the case in the future.

# To be done
* Simple script which keeps repo in sync with https://github.com/redhat-cop/controller_configuration
* Instructions on production grade implementation

# Getting started
Here's how to get started on implementing this architecture.

## Attention
Don't re-use this repository for anything else than test purposes. This repository and related ones are here to inspire you regarding what is possible. It is not:
1. Maintained to always be in sync with https://github.com/redhat-cop/controller_configuration
2. Production grade (all changes tested, vetted, etc)
If you think this is a good idea, do this yourself in repositories you control.

## Prerequisites
0. Password used in the current aap-synchronization.yml playbook for the admin user is: redhat123
1. Two preferrably empty Ansible Automation Platform controller clusters. Installation guide: https://access.redhat.com/documentation/en-us/red_hat_ansible_automation_platform/2.1/html/red_hat_ansible_automation_platform_installation_guide/index
2. A Load balancer infront of your two clusters, use whatever you like for this. In production type environments, it should be a load balancing cluster stretching your two datacenters or two availability zones / locations.
3. A version control system
4. Web hook support in your version control system or a CI-engine which can make calls to your AAP clusters when code change.
5. A willingness to go full automation-as-code

## Architectural overview

### Overview
![Alt text](img/overview-aap.png?raw=true "Overview")
Above you can see two separate AAP clusters installed in two separate data centers, receiving traffic from a load balancer.

### Overview - Execution flow
![Alt text](img/details-aap.png?raw=true "Details")
Job templates which controls the configuration state in the clusters are triggered from a version control system web hook or CI-enginee, so that changes are applied when they are merged to git.

### Detailed execution flow and responsibilities
![Alt text](img/flow-aap.png?raw=true "Details")
This setup supports a strong separation of responsiblity while allowing customers of the platform to own and manage their own configuration stored in separate git repositories. A bootstrap script configures the initial items in an empty cluster, this does initial config and creates a job template which configures the rest. Automation is kept in separate git respositories, as accordingly:
* Playbook and collection which configures the platform itself, plus setting up customers sync jobs: https://github.com/RedHatNordicsSA/controller_configuration
* Playbook and collection which applies the customers automation (it's here you define what people are allowed to do): https://github.com/RedHatNordicsSA/customer_configuration
* Customers configuration: https://github.com/RedHatNordicsSA/customer-x-as-code
* Customers playbooks: https://github.com/RedHatNordicsSA/customer-x-playbooks

## Installation (demo)
On _both_ your AAP controller clusters:
1. Clone this repository:
```
git clone https://github.com/RedHatNordicsSA/controller_configuration
```

2. Adapt bootstrap configuration and aap-synchronization.yml playbook
```
cp controller_configuration/bootstrap/bootstrap.cfg-example ~/.bootstrap.cfg
chmod 600 ~/.bootstrap.cfg
vi ~/.bootstrap.cfg
```

```
Generate an Ansible vault for your admin Controller user.
$ ansible-vault encrypt_string
password<CTRL-D><CTRL-D>
$
# Copy vault and put it into:
vi controller_configuration/aap-synchronization.yml
```

3. Run bootstrap script. This will setup the initial job template which will full in all the other configuration.
```
./bootstrap.sh
```

4. Create a vault on both clusters named "customer-x" with vault-id "customer-x", password redhat123. This mimics the customer manually adding the vault which keeps their secrets secret from the platform administrators.
5. Run the "Controller Synchronization" job template
6. Run the "Customer synchronization - Customer X" job template
7. Observe, adapt.
8. Connect CI-engine or version control system web hooks to run "Controller Synchronization" and "Customer synchronization - Customer X" job templates.
9. Connect monitoring system or advanced load blanacer to run "Controller Synchronization" and "Customer synchronization - Customer X" job templates at a point of failure.

## Setup (demo)
To add a new customer, you need:
* Add a vault "customer-y" with id "customer-y" manually in both clusters.
* A repository which holds the configuration, such as: https://github.com/RedHatNordicsSA/customer-x-as-code
* Define the following in https://github.com/RedHatNordicsSA/controller_configuration/tree/main/controller:
```
In organizations.yml:
---
controller_organizations:
  - name: customer-y
    galaxy_credentials:
      - "Red Hat Cloud Automation Hub"
      - "Ansible Galaxy"
...

In templates.yml:
---
controller_templates:
  - name: Customer synchronization - Customer Y
    description: Syncs in automation defined in https://github.com/RedHatNordicsSA/customer-y-as-code
    job_type: run
    inventory: "Demo Inventory"
    credentials: "automationvault"
    project: "customer_configuration"
    playbook: aap-synchronization.yml
    verbosity: 0
    credentials:
      - "automationvault"
      - "customer-y"
    extra_vars:
      customer_organization: customer-y
      customer_git_repo: https://github.com/RedHatNordicsSA/customer-y-as-code
      customer_git_branch: main
      controller_hostname: "{{ controller_hostname }}"
      controller_fqdn: "{{ controller_fqdn }}"
      load_balancer_fqdn: "{{ load_balancer_fqdn }}"
```

## Magic variables in Controller Synchronization job template
There are three variables which the bootstrap.sh script injects into your job template pointing to aap-synchronization.yml. Values are based on what you put into your settings in the bootstrap.cfg file. They are important and will therefor here be explained in greater detail.

Example:
```
controller_hostname: aap2two.sudo.net
controller_fqdn: aap2two.sudo.net
load_balancer_fqdn: loadbalancer.sudo.net
```
* controller_hostname is used to authenticate against the AAP cluster you are configuring.
* controller_fqdn is the FQDN used to reach the API of the cluster, can be the same as controller_hostname, we use this variable to make a call to /api/v2/ping to get an unique value called local_uuid, which identifies the cluster.
* load_balancer_fqdn is the load balancer you have put infront of your two clusters. It is used to make a call to the AAP clusters via the load balancer address, fetch the local_uuid value from whatever cluster which answers and then we use this to compare with the value we got when asking via the local clusters FQDN - if the two are the same, we know that the load balancer is pointing to the cluster we run - if this is the case, we'll activate whatever schedules are defined, otherwise, we'll disable them - as we don't want both clusters to actively run schedules.

# Red Hat Communities of Practice Controller Configuration Collection

![Ansible Lint](https://github.com/redhat-cop/controller_configuration/workflows/Ansible%20Lint/badge.svg)
![Galaxy Release](https://github.com/redhat-cop/controller_configuration/workflows/galaxy-release/badge.svg)
<!-- Further CI badges go here as above -->

This Ansible collection allows for easy interaction with an AWX or Ansible Controller server via Ansible roles using the AWX/Controller collection modules.

## REQUIREMENTS

The AWX.AWX OR ANSIBLE.CONTROLLER collections MUST be installed in order for this collection to work. It is recommended they be invoked in the playbook in the following way.

```yaml
---
- name: Playbook to configure ansible controller post installation
  hosts: localhost
  connection: local
  vars:
    controller_validate_certs: false
  collections:
    - awx.awx
```

## Included content

Click the `Content` button to see the list of content included in this collection.

## Installing this collection

You can install the redhat_cop controller_configuration collection with the Ansible Galaxy CLI:

```console
ansible-galaxy collection install redhat_cop.controller_configuration
```

You can also include it in a `requirements.yml` file and install it with `ansible-galaxy collection install -r requirements.yml`, using the format:

```yaml
---
collections:
  - name: redhat_cop.controller_configuration
    # If you need a specific version of the collection, you can specify like this:
    # version: ...
```

## Conversion from tower_configuration

If you were using a version of redhat_cop.tower_configuration, please refer to our Conversion Guide here: [Conversion Guide](docs/CONVERSION_GUIDE.md)

## Using this collection

The awx.awx or ansible.controller collection must be invoked in the playbook in order for ansible to pick up the correct modules to use.

The following command will invoke the playbook with the awx collection

```console
ansible-playbook redhat_cop.controller_configuration.configure_awx.yml
```

The following command will invoke the playbook with the ansible.controller collection

```console
ansible-playbook redhat_cop.controller_configuration.configure_controller.yml
```

Otherwise it will look for the modules only in your base installation. If there are errors complaining about "couldn't resolve module/action" this is the most likely cause.

```yaml
- name: Playbook to configure ansible controller post installation
  hosts: localhost
  connection: local
  vars:
    controller_validate_certs: false
  collections:
    - awx.awx
```

Define following vars here, or in `controller_configs/controller_auth.yml`
`controller_hostname: ansible-controller-web-svc-test-project.example.com`

You can also specify authentication by a combination of either:

- `controller_hostname`, `controller_username`, `controller_password`
- `controller_hostname`, `controller_oauthtoken`

The OAuth2 token is the preferred method. You can obtain the token through the preferred `controller_token` module, or through the
AWX CLI [login](https://docs.ansible.com/automation-controller/latest/html/controllercli/authentication.html)
command.

These can be specified via (from highest to lowest precedence):

- direct role variables as mentioned above
- environment variables (most useful when running against localhost)
- a config file path specified by the `controller_config_file` parameter
- a config file at `~/.controller_cli.cfg`
- a config file at `/etc/controller/controller_cli.cfg`

Config file syntax looks like this:

```ini
[general]
host = https://localhost:8043
verify_ssl = true
oauth_token = LEdCpKVKc4znzffcpQL5vLG8oyeku6
```

Controller token module would be invoked with this code:

```yaml
    - name: Create a new token using controller username/password
      awx.awx.token:
        description: 'Creating token to test controller jobs'
        scope: "write"
        state: present
        controller_host: "{{ controller_hostname }}"
        controller_username: "{{ controller_username }}"
        controller_password: "{{ controller_password }}"

```

### Controller Export

The awx command line can export json that is compatible with this collection.
More details can be found [here](examples/configs_export_model/README.md)

### See Also

- [Ansible Using collections](https://docs.ansible.com/ansible/latest/user_guide/collections_using.html) for more details.

## Release and Upgrade Notes

For details on changes between versions, please see [the changelog for this collection](CHANGELOG.rst).

## Roadmap

Adding the ability to use direct output from the awx export command in the roles along with the current data model.

## Contributing to this collection

We welcome community contributions to this collection. If you find problems, please open an issue or create a PR against the [Controller Configuration collection repository](https://github.com/redhat-cop/controller_configuration).
More information about contributing can be found in our [Contribution Guidelines.](https://github.com/redhat-cop/controller_configuration/blob/devel/.github/CONTRIBUTING.md)

## Licensing

GNU General Public License v3.0 or later.

See [LICENSE](https://www.gnu.org/licenses/gpl-3.0.txt) to see the full text.
