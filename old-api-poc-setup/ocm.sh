#!/bin/bash

OCMInit() {
  echo "OCM init"
  clusteradm init --wait --context ${CTX_HUB_CLUSTER}
}

OCMJoin() {
  join=$(clusteradm get token --context ${CTX_HUB_CLUSTER} | grep -o  'clusteradm join.*--cluster-name')
  echo "Joining Cluster: ${CLUSTER_NAME}"
  ${join} ${CLUSTER_NAME} --bundle-version='0.11.0' --feature-gates=RawFeedbackJsonString=true --context ${CONTEXT}
}

OCMAcceptCSR() {
  max_retry=18
  counter=0
  until clusteradm accept --clusters $CLUSTER_NAME --context ${CTX_HUB_CLUSTER}
  do
      sleep 10
      [[ counter -eq $max_retry ]] && echo "Failed!" && exit 1
      echo "Trying again. Try #$counter"
      ((++counter))
  done
}

installOCM() {
  ocmStatus=$(kubectl get --context ${CTX_HUB_CLUSTER} managedcluster $CLUSTER_NAME -o=jsonpath='{range .status.conditions[?(@.reason=="HubClusterAdminAccepted")]}{.status}{"\n"}{end}')

  if [[ "$ocmStatus" == "True" ]]; then
      echo "OCM already initialised."
  else
    OCMInit
    OCMJoin
    OCMAcceptCSR
  fi

  # Show OCM Pods
  kubectl -n open-cluster-management get pod --context ${CTX_HUB_CLUSTER}

  # Show OCM Cluster
  kubectl get managedcluster --context ${CTX_HUB_CLUSTER}
}


configureOCM() {
  kubectl --context $CONTEXT apply -f - <<EOF
apiVersion: cluster.open-cluster-management.io/v1beta2
kind: ManagedClusterSet
metadata:
  name: gateway-clusters
spec:
  clusterSelector:
    labelSelector:
      matchLabels:
        ingress-cluster: "true"
    selectorType: LabelSelector
EOF

  kubectl --context $CONTEXT apply -f - <<EOF
apiVersion: cluster.open-cluster-management.io/v1beta2
kind: ManagedClusterSetBinding
metadata:
  name: gateway-clusters
  namespace: multi-cluster-gateways
spec:
  clusterSet: gateway-clusters
EOF


  kubectl --context $CONTEXT apply -f - <<EOF
apiVersion: cluster.open-cluster-management.io/v1beta1
kind: Placement
metadata:
  name: http-gateway
  namespace: multi-cluster-gateways
spec:
  numberOfClusters: 2
  clusterSets:
    - gateway-clusters
EOF

  kubectl --context $CONTEXT label managedclusters ${CLUSTER_NAME} ingress-cluster=true
  kubectl --context $CONTEXT label managedclusters ${CLUSTER_NAME} kuadrant.io/lb-attribute-geo-code=EU
}

cleanupOCMHub() {
  echo "cleanupOCMHub. CTX_HUB_CLUSTER: ${CTX_HUB_CLUSTER}, CTX_MANAGED_CLUSTER: ${CTX_MANAGED_CLUSTER}, CLUSTER_NAME: ${CLUSTER_NAME}"
  clusteradm unjoin --cluster-name ${CLUSTER_NAME} --context ${CTX_MANAGED_CLUSTER}
  kubectl -n open-cluster-management-agent get pod --context ${CTX_MANAGED_CLUSTER}
  kubectl get klusterlet --context ${CTX_MANAGED_CLUSTER}
  kubectl delete managedcluster ${CLUSTER_NAME} --context ${CTX_HUB_CLUSTER}
}