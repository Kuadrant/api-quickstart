#!/bin/bash

installEchoApp() {
  kubectl --context $CONTEXT apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: echo-route
  labels:
    deployment: echo
spec:
  parentRefs:
  - kind: Gateway
    name: prod-web
    namespace: kuadrant-multi-cluster-gateways
  hostnames:
  - "echo.$ZONE_DOMAIN"
  rules:
  - backendRefs:
    - name: echo
      port: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: echo
spec:
  ports:
    - name: http-port
      port: 8080
      targetPort: http-port
      protocol: TCP
  selector:
    app: echo
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: echo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: echo
  template:
    metadata:
      labels:
        app: echo
    spec:
      containers:
        - name: echo
          image: docker.io/mendhak/http-https-echo
          ports:
            - name: http-port
              containerPort: 8080
              protocol: TCP
EOF
  kubectl wait --namespace=default --for=condition=available --timeout=300s deployment/echo
  showEchoAppDetails
}

showEchoAppDetails() {
  echo "Echo App: https://$(kubectl get httproute echo-route -n default -o jsonpath='{.spec.hostnames[0]}')"
  echo ""
}

cleanupEchoApp() {
  kubectl --context $CONTEXT delete -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: echo-route
  labels:
    deployment: echo
spec:
  parentRefs:
  - kind: Gateway
    name: prod-web
    namespace: kuadrant-multi-cluster-gateways
  hostnames:
  - "echo.$ZONE_DOMAIN"
  rules:
  - backendRefs:
    - name: echo
      port: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: echo
spec:
  ports:
    - name: http-port
      port: 8080
      targetPort: http-port
      protocol: TCP
  selector:
    app: echo
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: echo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: echo
  template:
    metadata:
      labels:
        app: echo
    spec:
      containers:
        - name: echo
          image: docker.io/mendhak/http-https-echo
          ports:
            - name: http-port
              containerPort: 8080
              protocol: TCP
EOF
}