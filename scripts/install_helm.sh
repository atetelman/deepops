#!/usr/bin/env bash

HELM_INSTALL_DIR=/usr/local/bin
HELM_INSTALL_SCRIPT_URL="${HELM_INSTALL_SCRIPT_URL:-https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get}"

# un-taint master nodes so they'll run the tiller pod
kubectl taint nodes --all node-role.kubernetes.io/master- 2>&1

# Install dependencies
. /etc/os-release
case "$ID_LIKE" in
    rhel*)
        if ! type curl >/dev/null 2>&1 ; then
            sudo yum -y install curl
        fi
        ;;
    debian*)
        if ! type curl >/dev/null 2>&1 ; then
            sudo apt -y install curl
        fi
        ;;
    *)
        echo "Unsupported Operating System $ID_LIKE"
        exit 1
        ;;
esac

if ! type helm >/dev/null 2>&1 ; then
    curl "${HELM_INSTALL_SCRIPT_URL}" > /tmp/get_helm.sh
    chmod +x /tmp/get_helm.sh
    #sed -i 's/sudo//g' /tmp/get_helm.sh
    mkdir -p ${HELM_INSTALL_DIR}
    HELM_INSTALL_DIR=${HELM_INSTALL_DIR} DESIRED_VERSION=v2.11.0 /tmp/get_helm.sh
fi

if type helm >/dev/null 2>&1 ; then
    helm init --client-only
else
    echo "Helm client not installed"
    exit 1
fi
