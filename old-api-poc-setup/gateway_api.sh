#!/bin/bash

installGWAPICRDs() {
  kubectl --context $CONTEXT apply -k "github.com/kuadrant/multicluster-gateway-controller.git/config/gateway-api?ref=main"
  kubectl --context $CONTEXT wait --timeout=5m crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --for=condition=Established
}