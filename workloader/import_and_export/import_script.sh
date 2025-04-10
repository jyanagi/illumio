#!/bin/bash
# This script was tested on the On-Prem Illumio PCE 24.2.20 using Workloader v12.0.14
# Perform these steps on the PCE that you would like to import the configurations to

# Import Label Dimensions
workloader label-dimension-import export-label-dimension.csv --update-pce --no-prompt --continue-on-error

# Import Labels
workloader label-import export-labels.csv --update-pce --no-prompt --continue-on-error

# Import Label Groups
workloader labelgroup-import export-labelgroups.csv --update-pce --no-prompt --continue-on-error --provision

# Import IP Lists
workloader ipl-import export-iplists.csv --update-pce --no-prompt --continue-on-error --provision

# Import Services
workloader svc-import export-services.csv --update-pce --no-prompt --continue-on-error --provision

# Import AD Groups
workloader adgroup-import export-adgroups.csv --update-pce --no-prompt --continue-on-error

# Import Rulesets
workloader ruleset-import export-rulesets.csv --update-pce --no-prompt --continue-on-error --provision

# Import Rules
workloader rule-import export-rules.csv --update-pce --no-prompt --continue-on-error --provision

echo "Import Complete!"
