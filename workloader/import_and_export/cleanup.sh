#!/bin/bash
# Use this script to remove all existing Rules, Rulesets, label groups, 
# labels, label dimensions, IP Lists, and Services

workloader rule-export --output-file delete_rules.csv && workloader delete delete_rules.csv --header href --update-pce --no-prompt --provision --continue-on-error

# Delete Segmentation Policy
workloader ruleset-export --output-file delete_rulesets.csv && workloader delete delete_rulesets.csv --header href --update-pce --no-prompt --provision --continue-on-error

# Delete Deny Rulesets

workloader deny-rule-export --output-file delete_denyrules.csv && workloader delete delete_denyrules.csv --header href --update-pce --no-prompt --provision --continue-on-error

# Delete IP Lists

workloader ipl-export --output-file delete_iplists.csv && workloader delete delete_iplists.csv --header href --update-pce --no-prompt --provision --continue-on-error

# Delete Label Groups

workloader labelgroup-export --output-file delete_label_groups.csv && workloader delete delete_label_groups.csv --header href --update-pce --no-prompt --provision --continue-on-error

# Delete Labels

workloader label-export --output-file delete_labels.csv && workloader delete delete_labels.csv --header href --update-pce --no-prompt --continue-on-error

# Delete Label Dimensions

workloader label-dimension-export --output-file delete_label-dimensions.csv && workloader delete delete_label-dimensions.csv --header href --update-pce --no-prompt --continue-on-error

# Delete Services

workloader svc-export --output-file delete_svcs.csv && workloader delete delete_svcs.csv --header href --update-pce --no-prompt --provision --continue-on-error

# Cleanup Files

rm -rf delete_*.csv
rm -rf workloader.log
