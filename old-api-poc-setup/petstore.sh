#!/bin/bash

installPetstoreAppSet() {
  kubectl --context $CONTEXT apply -f ./tmp/api-poc-petstore/argocd/ -n argocd
}