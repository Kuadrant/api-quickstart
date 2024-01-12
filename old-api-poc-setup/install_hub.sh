#!/bin/bash

# Pre-requisitites:
# `kubectl` context setup for cluster (update $CONTEXT below)
# `clusteradm` installed
# `jq` installed
# `kustomize` installed

export CONTEXT=kind-mgc-control-plane
export CTX_HUB_CLUSTER=$CONTEXT
export CTX_MANAGED_CLUSTER=$CONTEXT
export CLUSTER_NAME=local-cluster
export ISTIO_CTL=`pwd`/istio-1.19.3/bin/istioctl

# Zone: poc.stitch.hcpapps.net
export ZONE_ID=XXX
export ZONE_DOMAIN=xxx.example.com

source ./_sources.sh

fetchRepositories() {
  # fetch these repos:
  # - api-poc-petstore 
  # - api-poc-platform-engineer
  # - multicluster-gateway-controller
    
  mkdir -p ./tmp
  rm -rf ./tmp/api-poc-platform-engineer
  git clone --depth 1 https://github.com/Kuadrant/api-poc-platform-engineer.git ./tmp/api-poc-platform-engineer

  rm -rf ./tmp/api-poc-petstore
  git clone --depth 1 https://github.com/Kuadrant/api-poc-petstore.git ./tmp/api-poc-petstore

  rm -rf ./tmp/multicluster-gateway-controller
  git clone --depth 1 https://github.com/Kuadrant/multicluster-gateway-controller.git ./tmp/multicluster-gateway-controller

}

fetchRepositories

# OCM
installOCM
configureOCM

# Istio
installIstioCTL
installIstio

# Gatekeeper
installGatekeeper
configureGatekeeper
installGatekeeperScoreCard

# GW API CRDs
installGWAPICRDs

# MGC
installMGC
installKuadrant
configureMGC

# Service Registry
#installServiceRegistry

# Apicurio Studio
installApicurioStudio

# Metrics & Dashboards
installMetricsAndDashboards
serviceMonitor

# ArgoCD
installArgoCD

installPetstoreAppSet
