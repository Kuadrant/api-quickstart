#!/bin/bash

installMGC() {
  kubectl --context $CONTEXT apply -k "github.com/kuadrant/multicluster-gateway-controller.git/config/mgc-install-guide?ref=main"
  kubectl --context $CONTEXT wait --timeout=5m -n multicluster-gateway-controller-system deployment/mgc-controller-manager deployment/mgc-kuadrant-add-on-manager --for=condition=Available
  kubectl --context $CONTEXT wait --timeout=5m gatewayclass/kuadrant-multi-cluster-gateway-instance-per-cluster --for=condition=Accepted
}

createAWSCredentialsSecret() {
  envsubst < ./tmp/api-poc-platform-engineer/resources/aws_credentials_secret.yaml | kubectl --context $CONTEXT apply -f -
}

cleanupAWSCredentialsSecret() {
  envsubst < ./tmp/api-poc-platform-engineer/resources/aws_credentials_secret.yaml | kubectl --context $CONTEXT delete -f -
}

createManagedZone() {
  envsubst < ./tmp/api-poc-platform-engineer/resources/managedzone.yaml | kubectl --context $CONTEXT apply -f -
}

cleanupManagedZone() {
  envsubst < ./tmp/api-poc-platform-engineer/resources/managedzone.yaml | kubectl --context $CONTEXT delete -f -
}

createGateway() {
  envsubst < ./tmp/api-poc-platform-engineer/resources/gateway.yaml | kubectl --context $CONTEXT apply -f -
  kubectl --context $CONTEXT rollout restart deployment/prod-web-istio -n kuadrant-multi-cluster-gateways
}

cleanupGateway() {
  envsubst < ./tmp/api-poc-platform-engineer/resources/gateway.yaml | kubectl --context $CONTEXT delete -f -
  kubectl --context $CONTEXT rollout restart deployment/prod-web-istio -n kuadrant-multi-cluster-gateways
}

createTLSPolicy() {
  envsubst < ./tmp/api-poc-platform-engineer/resources/tlspolicy.yaml | kubectl --context $CONTEXT apply -f -
}

cleanupTLSPolicy() {
  envsubst < ./tmp/api-poc-platform-engineer/resources/tlspolicy.yaml | kubectl --context $CONTEXT delete -f -
}

# createDNSPolicy() {
#   envsubst < ./tmp/api-poc-platform-engineer/resources/dnspolicy.yaml | kubectl --context $CONTEXT apply -f -
# }

cleanupDNSPolicy() {
  envsubst < ./tmp/api-poc-platform-engineer/resources/dnspolicy.yaml | kubectl --context $CONTEXT delete -f -
}

placeGateway() {
  oc --context $CONTEXT adm policy add-scc-to-user anyuid -z prod-web-istio -n kuadrant-multi-cluster-gateways
  kubectl --context $CONTEXT label gateway prod-web "cluster.open-cluster-management.io/placement"="http-gateway" -n multi-cluster-gateways
  kubectl --context $CONTEXT get gateway -A
  kubectl --context $CONTEXT get dnsrecords.kuadrant.io -A
}

createConstraints() {
  envsubst < ./tmp/api-poc-platform-engineer/resources/gatekeeper_constraints.yaml | kubectl --context $CONTEXT apply -f -
}

configureMGC() {
  createAWSCredentialsSecret
  createManagedZone

  kubectl --context $CONTEXT wait --namespace multi-cluster-gateways --timeout=5m managedzone/mgc-dev-mz --for=condition=Ready
  kubectl --context $CONTEXT get managedzone -n multi-cluster-gateways

  createGateway
  createTLSPolicy
  placeGateway
  # createDNSPolicy
  createConstraints
}

cleanupMGC() {
  cleanupAWSCredentialsSecret
  cleanupManagedZone
  cleanupGateway
  cleanupTLSPolicy
  cleanupDNSPolicy
}