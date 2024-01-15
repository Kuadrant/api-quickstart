#!/bin/bash

#
# Copyright 2024 Red Hat, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


set -e pipefail

# TODO: load from GH?
echo "Loading quickstart scripts locally"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/.quickstartEnv"
source "${SCRIPT_DIR}/.kindUtils"
source "${SCRIPT_DIR}/.cleanupUtils"
source "${SCRIPT_DIR}/.deployUtils"
# source "${SCRIPT_DIR}/.startUtils"
# source "${SCRIPT_DIR}/.setupEnv"

# Depends on kustomize config in mgc repo, 'api-upstream' branch
if [ -z $MGC_BRANCH ]; then
  MGC_BRANCH=${MGC_BRANCH:="api-upstream"}
fi
if [ -z $MGC_ACCOUNT ]; then
  MGC_ACCOUNT=${MGC_ACCOUNT:="kuadrant"}
fi

# Ensure Thanos & Prometheus gets installed & configured
METRICS_FEDERATION=true

MGC_REPO=${MGC_REPO:="github.com/${MGC_ACCOUNT}/multicluster-gateway-controller.git"}
QUICK_START_HUB_KUSTOMIZATION=${MGC_REPO}/config/quick-start/control-cluster
QUICK_START_SPOKE_KUSTOMIZATION=${MGC_REPO}/config/quick-start/workload-cluster
PROMETHEUS_DIR=${MGC_REPO}/config/prometheus
PROMETHEUS_FOR_FEDERATION_DIR=${MGC_REPO}/config/prometheus-for-federation
PROMETHEUS_FOR_FEDERATION_API_DASHBOARDS_KUSTOMIZATION_DIR=${PROMETHEUS_FOR_FEDERATION_DIR}/api-dashboards
PROMETHEUS_FOR_FEDERATION_API_DASHBOARDS_GRAFANA_PATCH=https://raw.githubusercontent.com/${MGC_ACCOUNT}/multicluster-gateway-controller/${MGC_BRANCH}/config/prometheus-for-federation/api-dashboards/grafana_deployment_patch.yaml
THANOS_DIR=${MGC_REPO}/config/thanos

if [[ "${MGC_BRANCH}" != "main" ]]; then
  echo "setting MGC_REPO to use branch ${MGC_BRANCH}"
  QUICK_START_HUB_KUSTOMIZATION=${QUICK_START_HUB_KUSTOMIZATION}?ref=${MGC_BRANCH}
  QUICK_START_SPOKE_KUSTOMIZATION=${QUICK_START_SPOKE_KUSTOMIZATION}?ref=${MGC_BRANCH}
  echo "set QUICK_START_HUB_KUSTOMIZATION to ${QUICK_START_HUB_KUSTOMIZATION}"
  echo "set QUICK_START_SPOKE_KUSTOMIZATION to ${QUICK_START_SPOKE_KUSTOMIZATION}"
fi  

# Check for required env-vars
requiredENV

# Default config
if [[ -z "${LOG_LEVEL}" ]]; then
  LOG_LEVEL=1
fi
if [[ -z "${API_WORKLOAD_CLUSTERS_COUNT}" ]]; then
  API_WORKLOAD_CLUSTERS_COUNT=2
fi

# Make temporary directory for kubeconfig
mkdir -p ${TMP_DIR}

cleanupKind

# Setuyp kind clusters
setupClusters ${KIND_CLUSTER_CONTROL_PLANE} ${KIND_CLUSTER_WORKLOAD} ${port80} ${port443} ${API_WORKLOAD_CLUSTERS_COUNT}

# Deploy OCM hub
deployOCMHub ${KIND_CLUSTER_CONTROL_PLANE} "minimal"

# Deploy Quick start kustomize
deployQuickStartControl ${KIND_CLUSTER_CONTROL_PLANE}

# # Deploy MetalLb
deployMetalLB ${KIND_CLUSTER_CONTROL_PLANE} ${metalLBSubnetStart}
configureMetalLB ${KIND_CLUSTER_CONTROL_PLANE} ${metalLBSubnetStart}

# Deploy ingress controller
deployIngressController ${KIND_CLUSTER_CONTROL_PLANE}

# Deploy cert manager
deployCertManager ${KIND_CLUSTER_CONTROL_PLANE}

# Deploy Prometheus in the hub
deployPrometheusForFederation ${KIND_CLUSTER_CONTROL_PLANE} ${PROMETHEUS_FOR_FEDERATION_DIR}?ref=${MGC_BRANCH}

# Deploy Thanos components in the hub
deployThanos ${KIND_CLUSTER_CONTROL_PLANE} ${THANOS_DIR}

# Deploy Prometheus components in the hub
deployPrometheus ${KIND_CLUSTER_CONTROL_PLANE}

# Deploy API Dashboards in hub
installAPIDashboards ${KIND_CLUSTER_CONTROL_PLANE} ${PROMETHEUS_FOR_FEDERATION_API_DASHBOARDS_KUSTOMIZATION_DIR}?ref=${MGC_BRANCH} ${PROMETHEUS_FOR_FEDERATION_API_DASHBOARDS_GRAFANA_PATCH}

# Deploy Apicurito to the hub
deployApicurito ${KIND_CLUSTER_CONTROL_PLANE}


if [[ -n "${MGC_WORKLOAD_CLUSTERS_COUNT}" ]]; then
  for ((i = 1; i <= ${MGC_WORKLOAD_CLUSTERS_COUNT}; i++)); do
    deployQuickStartWorkload ${KIND_CLUSTER_WORKLOAD}-${i}
    configureMetalLB ${KIND_CLUSTER_WORKLOAD}-${i} $((${metalLBSubnetStart} + ${i}))
    deployOLM ${KIND_CLUSTER_WORKLOAD}-${i}
    deployOCMSpoke ${KIND_CLUSTER_WORKLOAD}-${i}
    configureManagedAddon ${KIND_CLUSTER_CONTROL_PLANE} ${KIND_CLUSTER_WORKLOAD}-${i}
    configureClusterAsIngress ${KIND_CLUSTER_CONTROL_PLANE} ${KIND_CLUSTER_WORKLOAD}-${i}
    deployPrometheusForFederation ${KIND_CLUSTER_WORKLOAD}-${i} ${PROMETHEUS_FOR_FEDERATION_DIR}?ref=${MGC_BRANCH}
  done
fi



kubectl config use-context kind-${KIND_CLUSTER_CONTROL_PLANE}


echo ""
echo "What's next...

      TBD"