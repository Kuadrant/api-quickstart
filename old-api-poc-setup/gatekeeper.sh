#!/bin/bash

installGatekeeper() {
  kubectl --context $CONTEXT apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: gatekeeper-operator-product
  namespace: openshift-operators
spec:
  channel: stable
  installPlanApproval: Automatic
  name: gatekeeper-operator-product
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

  kubectl --context $CONTEXT wait csv/gatekeeper-operator-product.v0.2.6-0.1697738427.p -n rhsso --timeout=300s --for "jsonpath=status.phase=Succeeded"

  kubectl --context $CONTEXT apply -f - <<EOF
apiVersion: operator.gatekeeper.sh/v1alpha1
kind: Gatekeeper
metadata:
  name: gatekeeper
spec:
  mutatingWebhook: "Enabled"
EOF

  kubectl --context $CONTEXT apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: gatekeeper-monitor
  namespace: openshift-gatekeeper-system
spec:
  podMetricsEndpoints:
    - port: metrics
  selector:
    matchLabels:
      gatekeeper.sh/system: 'yes'
EOF

  kubectl --context $CONTEXT wait --namespace=openshift-gatekeeper-system --for=condition=available --timeout=300s deployment/gatekeeper-audit
  kubectl --context $CONTEXT wait --namespace=openshift-gatekeeper-system --for=condition=available --timeout=300s deployment/gatekeeper-controller-manager

  echo "Gatekeeper Ready"
}

configureGatekeeper() {
  envsubst < ./tmp/api-poc-platform-engineer/resources/gatekeeper_constraints.yaml | kubectl --context $CONTEXT apply -f -
}

installGatekeeperScoreCard(){
  kubectl create namespace opa-exporter 
  kubectl --context $CONTEXT apply -f https://raw.githubusercontent.com/mcelep/opa-scorecard/master/exporter-k8s-resources/clusterrole.yaml
  kubectl --context $CONTEXT apply -f https://raw.githubusercontent.com/mcelep/opa-scorecard/master/exporter-k8s-resources/clusterrolebinding.yaml
  kubectl --context $CONTEXT apply -f https://raw.githubusercontent.com/mcelep/opa-scorecard/master/exporter-k8s-resources/deployment.yaml
  kubectl --context $CONTEXT apply -f https://raw.githubusercontent.com/mcelep/opa-scorecard/master/exporter-k8s-resources/service.yaml
  kubectl --context $CONTEXT apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: gatekeeper-scorecard
  namespace: opa-exporter
spec:
  endpoints:
    - port: 9141-9141
  selector:
    matchLabels:
      app: opa-exporter
EOF
}