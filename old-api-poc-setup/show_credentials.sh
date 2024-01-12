#!/bin/bash

# Pre-requisitites:
# You've ran install.sh & configure.sh

# Shows credentials + routes for all of the services on the cluster

export CONTEXT=kind-mgc-control-plane

source ./_sources.sh

showApicurioStudioDetails
showArgoCDDetails
showEchoAppDetails
showGrafanaDetails
showSSODetails