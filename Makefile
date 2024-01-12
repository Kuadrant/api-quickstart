
# Setting SHELL to bash allows bash commands to be executed by recipes.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

include ./hack/make/*.make


##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development

.PHONY: clean
clean: ## Clean up temporary files.
	-rm -rf ./tmp
	-rm -rf ./config/**/charts

.PHONY: local-setup-api
local-setup-api: local-setup-kind-api local-setup-mgc-api ## Setup multi cluster traffic controller locally using kind.
	$(info Setup is done! Enjoy)
	$(info Consider using local-setup-kind-api or local-setup-mgc-api targets to separate kind clusters creation and deployment of resources)

.PHONY: local-setup-kind-api
local-setup-kind-api: kind yq ## Setup kind clusters for multi cluster traffic controller.
	./hack/local-setup-kind-api.sh

.PHONY: local-setup-mgc-api
local-setup-mgc-api: kustomize helm yq dev-tls istioctl operator-sdk clusteradm subctl ## Setup multi cluster traffic controller locally onto kind clusters.
	./hack/local-setup-mgc-api.sh

.PHONY: local-cleanup
local-cleanup: kind ## Cleanup kind clusters created by local-setup
	./hack/local-cleanup-kind.sh
	$(MAKE) clean

.PHONY: local-cleanup-mgc
local-cleanup-mgc: ## Cleanup MGC from kind clusters
	./hack/local-cleanup-mgc.sh

.PHONY: dev-tls
dev-tls: $(DEV_TLS_CRT) ## Generate dev tls webhook cert if necessary.
$(DEV_TLS_CRT):
	openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout $(DEV_TLS_KEY) -out $(DEV_TLS_CRT) -subj "/C=IE/O=Red Hat Ltd/OU=HCG/CN=webhook.172.31.0.2.nip.io" -addext "subjectAltName = DNS:webhook.172.31.0.2.nip.io"

.PHONY: clear-dev-tls
clear-dev-tls:
	-rm -f $(DEV_TLS_CRT)
	-rm -f $(DEV_TLS_KEY)

##@ Deployment
ifndef ignore-not-found
  ignore-not-found = false
endif
