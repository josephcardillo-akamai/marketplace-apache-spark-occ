#!/bin/bash
set -e
DEBUG="NO"
if [ "${DEBUG}" == "NO" ]; then
  trap "cleanup $? $LINENO" EXIT
fi

function cleanup {
  if [ "$?" != "0" ]; then
    echo "PLAYBOOK FAILED. See /var/log/stackscript.log for details."
    rm ${HOME}/.ssh/id_ansible_ed25519{,.pub}
    destroy
    exit 1
  fi
}

# utility functions
function destroy {
  if [ -n "${DISTRO}" ] && [ -n "${DATE}" ]; then
    ansible-playbook destroy.yml --extra-vars "instance_prefix=${DISTRO}-${DATE}"
  else
    ansible-playbook destroy.yml
  fi
}

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
  local LINODE_PARAMS=($(curl -sH "Authorization: Bearer ${TOKEN_PASSWORD}" "https://api.linode.com/v4/linode/instances/${LINODE_ID}" | jq -r .type,.region,.image))
  local LINODE_TAGS=$(curl -sH "Authorization: Bearer ${TOKEN_PASSWORD}" "https://api.linode.com/v4/linode/instances/${LINODE_ID}" | jq -r .tags)
  local VARS_PATH="${WORK_DIR}/group_vars/spark/vars"
  local TEMP_ROOT_PASS=$(openssl rand -base64 32)
  local SPARK_HOME="/opt/spark"
  master_ssh_key

  # write vars file
  sed 's/  //g' <<EOF > ${VARS_PATH}
  # user vars
  sudo_username: ${SUDO_USERNAME}
  token_password: ${TOKEN_PASSWORD}

  # deployment vars
  uuid: ${UUID}
  ssh_keys: ${ANSIBLE_SSH_PUB_KEY}
  instance_prefix: ${INSTANCE_PREFIX}
  type: ${LINODE_PARAMS[0]}
  region: ${LINODE_PARAMS[1]}
  image: ${LINODE_PARAMS[2]}
  linode_tags: ${LINODE_TAGS}
  root_pass: ${TEMP_ROOT_PASS}
  
  # spark vars
  cluster_name: ${CLUSTER_NAME}
  cluster_size: ${CLUSTER_SIZE}
  spark_user: ${SPARK_USER}
  spark_home: ${SPARK_HOME}

  # ssl/tls
  soa_email_address: ${SOA_EMAIL_ADDRESS}
EOF
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

# main
case $1 in
    build) "$@"; exit;;
    deploy) "$@"; exit;;
esac
