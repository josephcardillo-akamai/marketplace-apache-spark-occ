#!/bin/bash
set -e
DEBUG="NO"
if [ "${DEBUG}" == "NO" ]; then
  trap "cleanup $? $LINENO" EXIT
fi

# constants
readonly ROOT_PASS=$(sudo cat /etc/shadow | grep root)
readonly LINODE_PARAMS=($(curl -sH "Authorization: Bearer ${TOKEN_PASSWORD}" "https://api.linode.com/v4/linode/instances/${LINODE_ID}" | jq -r .type,.region,.image))
readonly LINODE_TAGS=$(curl -sH "Authorization: Bearer ${TOKEN_PASSWORD}" "https://api.linode.com/v4/linode/instances/${LINODE_ID}" | jq -r .tags)
readonly VARS_PATH="./group_vars/spark/vars"

# utility functions
function destroy {
  if [ -n "${DISTRO}" ] && [ -n "${DATE}" ]; then
    ansible-playbook destroy.yml --extra-vars "instance_prefix=${DISTRO}-${DATE}"
  else
    ansible-playbook destroy.yml
  fi
}

# function secrets {
#   local SECRET_VARS_PATH="./group_vars/spark/secret_vars"
#   local VAULT_PASS=$(openssl rand -base64 32)
#   local TEMP_ROOT_PASS=$(openssl rand -base64 32)
#   echo "${VAULT_PASS}" > ./.vault-pass
#   cat << EOF > ${SECRET_VARS_PATH}
# `ansible-vault encrypt_string "${TEMP_ROOT_PASS}" --name 'root_pass'`
# `ansible-vault encrypt_string "${TOKEN_PASSWORD}" --name 'token'`
# EOF
# }

function master_ssh_key {
    ssh-keygen -o -a 100 -t ed25519 -C "ansible" -f "${HOME}/.ssh/id_ansible_ed25519" -q -N "" <<<y >/dev/null
    export ANSIBLE_SSH_PUB_KEY=$(cat ${HOME}/.ssh/id_ansible_ed25519.pub)
    export ANSIBLE_SSH_PRIV_KEY=$(cat ${HOME}/.ssh/id_ansible_ed25519)
    export SSH_KEY_PATH="${HOME}/.ssh/id_ansible_ed25519"
    chmod 700 ${HOME}/.ssh
    chmod 600 ${SSH_KEY_PATH}
    eval $(ssh-agent)
    ssh-add ${SSH_KEY_PATH}
    echo -e "\nprivate_key_file = ${SSH_KEY_PATH}" >> ansible.cfg
}

# production
function build {
  # secrets
  master_ssh_key

  # write vars file
  sed 's/  //g' <<EOF > ${VARS_PATH}
  
  # deployment vars
  uuid: ${UUID}
  ssh_keys: ${ANSIBLE_SSH_PUB_KEY}
  instance_prefix: ${INSTANCE_PREFIX}
  cluster_name: ${CLUSTER_NAME}
  type: ${LINODE_PARAMS[0]}
  region: ${LINODE_PARAMS[1]}
  image: ${LINODE_PARAMS[2]}
  root_pass: ${ROOT_PASS}
  
  linode_tags: ${LINODE_TAGS}
  
  # sudo user
  sudo_username: ${SUDO_USERNAME}

  soa_email_address: ${SOA_EMAIL_ADDRESS}
  spark_user: ${SPARK_USER}
  cluster_size: ${CLUSTER_SIZE}
EOF
  if [[ -n ${TOKEN_PASSWORD} ]]; then
    echo "token_password: ${TOKEN_PASSWORD}" >> ${VARS_PATH};
  else echo "No API token entered";
  fi

  if [[ -n ${DOMAIN} ]]; then
    echo "domain: ${DOMAIN}" >> ${VARS_PATH};
  else echo "default_dns: $(hostname -I | awk '{print $1}'| tr '.' '-' | awk {'print $1 ".ip.linodeusercontent.com"'})" >> ${VARS_PATH};
  fi

  if [[ -n ${SUBDOMAIN} ]]; then
    echo "subdomain: ${SUBDOMAIN}" >> ${VARS_PATH};
  else echo "subdomain: www" >> ${VARS_PATH};
  fi
}

function deploy { 
    for playbook in provision.yml site.yml; do ansible-playbook -v -i hosts $playbook; done
}

function ansible:deploy {
  ansible-playbook provision.yml
  for playbook in provision.yml ansible-playbook -i hosts -vv site.yml --extra-vars "root_password=${ROOT_PASS}"
}

## cleanup ##
function cleanup {
  if [ "$?" != "0" ] || [ "$SUCCESS" == "true" ]; then
    cd ${HOME}
    if [ -d "/tmp/marketplace-apache-spark-occ" ]; then
      rm -rf /tmp/marketplace-apache-spark-occ
    fi
    if [ -f "/usr/local/bin/run" ]; then
      rm /usr/local/bin/run
    fi
  fi
}

# main
case $1 in
    build) "$@"; exit;;
    deploy) "$@"; exit;;
esac
