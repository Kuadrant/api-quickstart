#!/bin/bash

installMetricsAndDashboards() {
  export SECRET=`oc get secret -n openshift-user-workload-monitoring | grep  prometheus-user-workload-token | head -n 1 | awk '{print $1 }'`
  export TOKEN=`echo $(oc get secret $SECRET -n openshift-user-workload-monitoring -o json | jq -r '.data.token') | base64 -d`
  envsubst < ./tmp/multicluster-gateway-controller/config/prometheus-for-federation/ocp_monitoring/grafana_datasources.yaml.template > ./tmp/multicluster-gateway-controller/config/prometheus-for-federation/ocp_monitoring/grafana_datasources.yaml
  kustomize --load-restrictor LoadRestrictionsNone build ./tmp/multicluster-gateway-controller/config/prometheus-for-federation/ocp_monitoring --enable-helm | kubectl apply -f -
  kubectl patch clusterrole kube-state-metrics-stitch-poc --type=json -p "$(cat ./metrics-clusterrole-patch.yaml)"
  grafanaHost=$(kubectl get --context $CONTEXT route grafana -n monitoring -o=jsonpath='{.spec.host}')
  kubectl delete configmap grafana-stitch --namespace=monitoring
  kubectl create configmap grafana-stitch --namespace=monitoring --from-file=./stitch.json
  kubectl delete configmap grafana-stitch-platform-eng-dashboard --namespace=monitoring
  kubectl create configmap grafana-stitch-platform-eng-dashboard --namespace=monitoring --from-file=./stitch_platform_eng_dashboard.json
  kubectl delete configmap grafana-stitch-gatekeeper-dashboard --namespace=monitoring
  kubectl create configmap grafana-stitch-gatekeeper-dashboard --namespace=monitoring --from-file=./gatekeeper_dashboard.json

  kubectl patch deployment grafana -n monitoring --type=json -p "$(cat ./grafana_deployment_patch.yaml)"
  kubectl rollout restart deployment/grafana -n monitoring
  showGrafanaDetails
}

showGrafanaDetails() {
  grafanaHost=$(kubectl get --context $CONTEXT route grafana -n monitoring -o=jsonpath='{.spec.host}')
  echo "Grafana: https://$grafanaHost"
  echo "Username/Password: admin"
  echo ""
}

serviceMonitor() {
  kubectl --context $CONTEXT label authorino -n kuadrant-system authorino app=authorino
  # Also label the metrics Service directly as the authorino operator doesn't reconcile already existing resources
  # Should the reconciler try to reconcile the Service at a later point (e.g. operator gets killed/restarted),
  # it should include the labels from the Authorino CR and set the state the same as what we want anyways.
  kubectl --context $CONTEXT label service -n kuadrant-system authorino-controller-metrics app=authorino

  kubectl --context $CONTEXT apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: limitador
  namespace: kuadrant-system
spec:
  endpoints:
    - port: http
  selector:
    matchLabels:
      app: limitador
EOF

  kubectl --context $CONTEXT apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: authorino
  namespace: kuadrant-system
spec:
  endpoints:
    - port: http
  selector:
    matchLabels:
      app: authorino
EOF
}