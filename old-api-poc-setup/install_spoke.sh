#!/bin/bash
source ./_sources.sh

export CONTEXT=default/api-stitchpoc2-zpoe-p1-openshiftapps-com:6443/jasonmadigan
export CTX_HUB_CLUSTER=default/api-stitchpoc1-cdnq-p1-openshiftapps-com:6443/jasonmadigan
export CTX_MANAGED_CLUSTER=$CONTEXT
export CLUSTER_NAME=spoke


setupOCMSpoke() {
  ocmStatus=$(kubectl get --context ${CTX_HUB_CLUSTER} managedcluster $CLUSTER_NAME -o=jsonpath='{range .status.conditions[?(@.reason=="HubClusterAdminAccepted")]}{.status}{"\n"}{end}')

  if [[ "$ocmStatus" == "True" ]]; then
      echo "OCM already initialised."
  else
    OCMJoin
    OCMAcceptCSR
  fi

  # Show OCM Pods
  kubectl -n open-cluster-management get pod --context ${CTX_HUB_CLUSTER}

  # Show OCM Cluster
  kubectl get managedcluster --context ${CTX_HUB_CLUSTER}
  sleep 2 #TODO: wait
  kubectl --context $CTX_HUB_CLUSTER label managedclusters ${CLUSTER_NAME} ingress-cluster=true
  kubectl --context $CTX_HUB_CLUSTER label managedcluster ${CLUSTER_NAME} kuadrant.io/lb-attribute-geo-code=US
}

cleanupOCMSpoke() {
  clusteradm unjoin --cluster-name ${CLUSTER_NAME} --context ${CTX_MANAGED_CLUSTER}
  kubectl -n open-cluster-management-agent get pod --context ${CTX_MANAGED_CLUSTER}
  kubectl get klusterlet --context ${CTX_MANAGED_CLUSTER}
  kubectl delete managedcluster ${CLUSTER_NAME} --context ${CTX_HUB_CLUSTER}
}

installKuadrantAddonToSpoke() {
  kubectl --context ${CTX_HUB_CLUSTER} apply -k "github.com/kuadrant/multicluster-gateway-controller.git/config/service-protection-install-guide?ref=main" -n $CLUSTER_NAME
  kubectl --context ${CTX_HUB_CLUSTER} annotate managedclusteraddon kuadrant-addon "addon.open-cluster-management.io/values"='{"CatalogSource":"kuadrant-operator", "Channel":"stable", "CatalogSourceNS":"openshift-marketplace"}' --overwrite -n $CLUSTER_NAME

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
  image: quay.io/kuadrant/kuadrant-operator-catalog:v0.4.0
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 60m
EOF

}

setupOCMSpoke
#cleanupOCMSpoke

# Istio
installIstioCTL
installIstio

installGWAPICRDs

installKuadrantAddonToSpoke
