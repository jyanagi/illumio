#!/bin/bash
# This script was tested on the On-Prem Illumio PCE 24.2.20 using Workloader v12.0.14
# Perform these steps on the PCE that you would like to export the configurations from

# Remove previous export files
rm -rf export-*.csv

# Export Label Dimensions
workloader label-dimension-export --no-href --output-file export-label-dimension.csv

# Export Labels
workloader label-export --no-href --output-file export-labels.csv

# Export Label Groups
workloader labelgroup-export --no-href --output-file export-labelgroups.csv

# Export IP Lists
workloader ipl-export --no-href --output-file export-iplists.csv

# Export Services
workloader svc-export --no-href --output-file export-services.csv

# Export AD Groups
workloader adgroup-export --no-href --output-file export-adgroups.csv

# Export Rules
workloader rule-export --no-href --output-file export-rules.csv

# Export Rulesets
workloader ruleset-export --no-href --output-file export-rulesets.csv

echo "Export Complete!"
