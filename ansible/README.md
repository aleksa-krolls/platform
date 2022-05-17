# Platform Deploy

## Prerequisites

- Linux OS to run commands
- Install Ansible
- Ansible Docker Community Collection installed

  ```bash
  ansible-galaxy collection install community.docker
  ```

## Infrastructure and Servers

Please see the `/inventories/{ENVIRONMENT}/hosts` file for IP details of the designated services.

## Ansible

### SSH Access

To authenticate yourself on the remote servers your ssh key will need to be added to the `users` var in the _/inventories/{ENVIRONMENT}/group_vars/all.yml_.

An authorised user will need to run the `provision_servers.yml` playbook to add your ssh key to the servers.

### Configuration

To run a playbook you should do:

```bash
ansible-playbook \
  --ask-vault-pass \
  --become \
  --inventory=inventories/<INVENTORY> \
  --user=ubuntu \
  playbooks/<PLAYBOOK>.yml
```

OR to run all provisioning playbooks with the development inventory (most common for setting up dev server), use:

```bash
ansible-playbook \
  --ask-vault-pass \
  --become \
  --inventory=inventories/development \
  --user=ubuntu \
  playbooks/provision.yml
```

### Vault

The vault password required for running the playbooks can be found in the `database.kdbx` KeePass file.

To encrypt a new secret with vault run:

```bash
echo -n '<YOUR SECRET>' | ansible-vault encrypt_string
```

> The __New password__ is the original Ansible Vault password.

## Keepass

Copies of all the passwords used here are kept in the encrypted `database.kdbx` file.

> Please ask your admin for the decryption password.