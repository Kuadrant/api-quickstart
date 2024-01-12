**TODO:** Automate creation & fetch of serviceaccount bearerToken used for ArgoCD clusters.

To do this manually, you have to create the serviceaccount & perms in each cluster:

`kubectl apply -n default -f ./argocd-clusters`

Then fetch the token from an annotation (because it's openshift. Usually the token is in data.token)

`kubectl get serviceaccount argocd-manager -n default -o=jsonpath='{.secrets[0].name}' | xargs kubectl get secret -n default -o=jsonpath='{.metadata.annotations.openshift\.io/token-secret\.value}'`
