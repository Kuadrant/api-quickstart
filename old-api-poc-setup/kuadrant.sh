#!/bin/bash

installKuadrant() {
  # Note: installing pre-release Kuadrant Addon: https://gist.github.com/jasonmadigan/bde64d4967fdbb740fd8eb876f2579dc
  echo "Creating CatalogSource"
  kubectl --context $CONTEXT apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: kuadrant-operator
  namespace: openshift-marketplace
spec:
  displayName: Kuadrant
  grpcPodConfig:
    securityContextConfig: restricted
  image: quay.io/kuadrant/kuadrant-operator-catalog:v0.4.1
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 60m
EOF

  kubectl --context $CONTEXT wait --namespace openshift-marketplace --timeout=5m catalogsource/kuadrant-operator --for="jsonpath=status.connectionState.lastObservedState=READY"

  kubectl --context $CONTEXT apply -f - <<EOF
apiVersion: addon.open-cluster-management.io/v1alpha1
kind: ManagedClusterAddOn
metadata:
  annotations:
    addon.open-cluster-management.io/values: '{"CatalogSource":"kuadrant-operator", "Channel":"stable", "CatalogSourceNS":"openshift-marketplace"}'
  name: kuadrant-addon
  namespace: $CLUSTER_NAME
spec:
  installNamespace: open-cluster-management-agent-addon
EOF

  kubectl wait --timeout=5m -n kuadrant-system kuadrant/kuadrant-sample --for=condition=Ready  --context $CONTEXT
}