#!/bin/bash
#
# This is a modified version of the generic Dask/Rapids deployment script found
# at scripts/k8s_deploy_rapids_dask.sh.

set -x

NAMESPACE="rapids" # TODO: Pass through different ns end to end
if [ -z "${NAMESPACE}" ]; then
    NAMESPACE="rapids"
fi


function build_image() {
  echo "Building custom dask/rapids image"
  pushd docker
  docker build -t dask-rapids .
  # TODO: Push the docker  image
  popd
}

function tear_down() {
  echo "Tearing down existing resources"
  # Delete existing resources
  helm list ${NAMESPACE} | grep ${NAMESPACE} 2> /dev/null 1> /dev/null
  if [ "${?}" == "0" ]; then
    read -r -p "Helm resources already exist, would you  like to delete them? (yes/no)" response
    case "$response" in
      [yY][eE][sS]|[yY])
        helm delete --purge ${NAMESPACE}
	;;
      *)
        echo "Quitting install"
	exit
	;;
    esac
  fi
  kubectl get ns rapids 2> /dev/null 1> /dev/null
  if [ "${?}" == "0" ]; then
    read -r -p "Kubernetes resources already exist, would you  like to delete them? (yes/no)" response
    case "$response" in
      [yY][eE][sS]|[yY])
        kubectl delete ns ${NAMESPACE}
	;;
      *)
        echo "Quitting install"
	exit
	;;
    esac
  fi	  
  sleep 5
}

function stand_up() {
  echo "installing dask via helm"
  helm install -n ${NAMESPACE} --namespace ${NAMESPACE} --values helm/rapids-dask.yml stable/dask
  kubectl create -f k8s/rapids-dask-sa.yml
  sleep 5
}


function copy_config() {
  echo "Copying dask-worker yaml file into running jupyter container"
  kubectl -n ${NAMESPACE} scale deployment rapids-dask-worker --replicas=1
  # Wait for containers to initialize
  sleep 60 

  # Copy worker spec over to Jupyter for Manual cluster  definition
  ## Get the names of the running pods
  worker_name=$(kubectl -n ${NAMESPACE} get pods --no-headers=true -o custom-columns=:metadata.name | grep worker | tail -n1)
  jupyter_name=$( kubectl -n ${NAMESPACE} get pods --no-headers=true -o custom-columns=:metadata.name | grep jupyter | tail -n1)
  spec="k8s/worker-spec-dynamic.yaml"

  ## Copy the yaml files into the pods after parsing some invalid information out
  kubectl -n ${NAMESPACE} get pods --export -o yaml ${worker_name} > ${spec}.tmp
  cat ${spec}.tmp | grep -v creationTimestamp | awk -F'status:' '{print $1}' > ${spec}
  kubectl -n ${NAMESPACE} cp ${spec} ${jupyter_name}:/rapids/notebooks

  # Scale worker Deployment to 0 so it can be controlled via Jupyter rather than k8s directly
  # XXX: This is an issue until we figure  out how to  join the existing cluster/deployment with the dask_kubernetes flow
  kubectl -n ${NAMESPACE} scale deployment rapids-dask-worker --replicas=0
}

function get_url() {
  host_ip=""
  jupyter_port="$(kubectl -n rapids get svc rapids-dask-jupyter -ocustom-columns=:.spec.ports[0].nodePort)"
  jupyter_ip="$(kubectl -n rapids get svc rapids-dask-jupyter -ocustom-columns=:.status.loadBalancer.ingress[0].ip)"
  dask_port="$(kubectl -n rapids get svc rapids-dask-jupyter -ocustom-columns=:.spec.ports[0].nodePort)"
  dask_ip="$(kubectl -n rapids get svc rapids-dask-scheduler -ocustom-columns=:.status.loadBalancer.ingress[0].ip)"
  
  echo "Jupyter IP (default password == 'dask'): ${jupyter_ip}"
  echo "Jupyter nodePort: ${jupyter_port}"
  echo "Dask IP: ${dask_ip}"
  echo "Dask nodePort: ${dask_port}"
  
}

tear_down
build_image
stand_up
copy_config
get_url
