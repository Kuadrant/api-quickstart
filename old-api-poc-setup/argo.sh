#!/bin/bash

installArgoCD() {
  kubectl --context $CONTEXT apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: argocd
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: argocd
  namespace: openshift-operators
spec:
  channel: alpha
  installPlanApproval: Automatic
  name: argocd-operator
  source: community-operators
  sourceNamespace: openshift-marketplace
  startingCSV: argocd-operator.v0.7.0
EOF

  sleep 5
  kubectl --context $CONTEXT wait deployment.apps/argocd-operator-controller-manager -n openshift-operators --timeout=300s --for="condition=Available=True"

  kubectl --context $CONTEXT apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: ArgoCD
metadata:
  name: argocd
  namespace: argocd
spec:
  extraConfig:
    resource.compareoptions: |
      ignoreResourceStatusField: all
    kustomize.buildOptions: --load-restrictor LoadRestrictionsNone --enable-helm
  applicationSet: {}
  grafana:
    enabled: false
  prometheus:
    enabled: false
  server:
    route:
      enabled: true
EOF

  # TODO: replace this with a simpler wait.
  while ! kubectl --context $CONTEXT get secret argocd-cluster -n argocd &>/dev/null; do
    echo "Waiting for argocd-cluster secret to be created..."
    sleep 5
  done
  echo "argocd-cluster secret is now available."

  kubectl --context $CONTEXT apply -f ./argocd/applications/infra-all.yaml
  # Apply the SealedSecret for this repo & local cluster as ArgoCD won't be able to sync them first time
  kubectl --context $CONTEXT apply -f ./argocd/repos/api-poc-setup.yaml
  kubectl --context $CONTEXT apply -f ./argocd/clusters/local-cluster.yaml

  showArgoCDDetails
}

showArgoCDDetails() {
  argoHost=$(kubectl --context $CONTEXT get route argocd-server -n argocd -o=jsonpath='{.spec.host}')
  argoPassword=$(kubectl --context $CONTEXT -n argocd get secret argocd-cluster -o jsonpath='{.data.admin\.password}' | base64 -d)

  echo "ArgoCD: https://$argoHost"
  echo "ArgoCD Username: admin"
  echo "ArgoCD Password: $argoPassword"
  echo ""
}