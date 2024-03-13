#!/bin/bash
#########################################################################################################
#
# Shell script created by Jeff Yanagi
# Last modified March 13, 2024
# v1.0
#
# Change Log:
# - 3.13.2024: Optimized json wrapper (line 103)
# - 3.5.2024: Initial Commit
#
# This script demonstrates 3rd Party Integration with Illumio PCE
# and Nessus Vulnerability Scanner (either Professional or Essentials
#
# Outcome of execution is to automatically label VENs/Managed Workloads
# as "Risky" based on Nessus Vulnerability Scan AND CISA's Known
# Exploited Vulnerabilities list for ransomware attacks.
#
# REQUIREMENTS:
# Create a credentials file with token information for access to both
# Nessus Platform and Illumio PCE
#
# Modify variables to match your organizations information...
# Uncomment "wget -N https://www.cisa.gov/sites/default/files/csv/known_exploited_vulnerabilities.csv
#
##########################################################################################################

# Use Credentials File for Authentication (replace with your file location)
source .credentials

nessus_url=nessus.zt.skool.haus:8834
pce_url=pce-01.zt.skool.haus:8443
org_id=1
wget -N https://www.cisa.gov/sites/default/files/csv/known_exploited_vulnerabilities.csv

# Create New Label Dimension labeled "Risky"
label_dimension=$(curl -s -k -X GET https://$pce_url/api/v2/orgs/$org_id/label_dimensions -u $ilo_api:$ilo_secret | jq -r '.[] | .display_name' >/dev/null 2>&1)
if $label_dimension | grep -q "Risk"; then
  label=$(curl -s -k -X GET https://$pce_url/api/v2/orgs/$org_id/labels -u $ilo_api:$ilo_secret | jq '.[] | select(.value == "Risky") | .href')
else
  curl -s -k -X POST https://$pce_url/api/v2/orgs/$org_id/label_dimensions -u $ilo_api:$ilo_secret -H "Content-Type: application/json" -d '{"key":"RI","display_name":"Risk","display_info":{"icon":"critical","initial":"RI","background_color":"#ff0000","foreground_color":"#ffffff","display_name_plural":"Risk"}}' >/dev/null 2>&1
  curl -s -k -X POST https://$pce_url/api/v2/orgs/$org_id/labels -u $ilo_api:$ilo_secret -H "Content-Type: application/json" -d '{"key":"RI","value":"Risky"}' >/dev/null 2>&1
  label=$(curl -s -k -X GET https://$pce_url/api/v2/orgs/$org_id/labels -u $ilo_api:$ilo_secret | jq '.[] | select(.value == "Risky") | .href')
fi

# Only parse for CVEs listed under "knownRansomwareCampaignUse"
known_vulns=$(awk -F ',' '$9=="Known" {print $1}' known_exploited_vulnerabilities.csv)
num_vulns=$(grep -wi "Known" known_exploited_vulnerabilities.csv | wc -l)

# Convert CVEs into an Array
IFS=$'\n' read -r -d '' -a cves <<< "$known_vulns"

# Nessus API call to pull scan information
output=$(curl -s -k -X GET -H "X-ApiKeys: accessKey=$access_key; secretKey=$secret_key" https://$nessus_url/scans | jq -r '.scans[] | .name')

# Convert Output of Scans to an Array
IFS=$'\n' read -r -d '' -a scans <<< "$output"
echo ""
echo "Select the Nessus Scan you would like to parse:"
# Print Array as Itemized/Numbered List
for i in "${!scans[@]}"; do
  echo "$((i+1)). ${scans[i]}"
done

# Prompt User to Select Scan Number
read -p "Enter the number of the scan you want to select: " selection
echo ""
# Validate Selection of Scan

if [[ $selection =~ ^[0-9]+$ && $selection -ge 1 && $selection -le ${#scans[@]} ]]; then

  # Scan Selection
  selected_scan="${scans[selection-1]}"
  echo "You selected: $selected_scan"
  output=$(curl -s -k -X GET -H "X-ApiKeys: accessKey=$access_key; secretKey=$secret_key" https://$nessus_url/scans | jq -r --arg selected_scan "$selected_scan" '.scans[] | select(.name == $selected_scan) | .id')
  echo -e "\n***********************************************************"
  echo -e "Cross-referencing Nessus Vulnerability Scan results against\nCISA Known Exploited Vulnerabilities Database (CVEs with\nknown Ransomware Campaign Use) [$num_vulns CVEs]"
  echo -e "***********************************************************\n"
  echo "Please wait as this process may take a few moments to complete"

  # Pull Hostnames from Scan Results for CVE
  for cve in "${cves[@]}"; do

    hostnames=$(curl -s -k -X GET -H "X-ApiKeys: accessKey=$access_key; secretKey=$secret_key" https://$nessus_url/scans/$output | jq -r --arg cve "$cve" '.prioritization.plugins[] | select(.pluginattributes.cvss_score_source == $cve) | .hosts | map(.hostname)[]')

    # Convert Hostname Output to Array
    IFS=$'\n' read -r -d '' -a hostnames <<< "$hostnames"

    # For loop to Assign "Risky" Label to Workloads that have exposure to Ransomware Vulnerabilities
    for hostname in "${hostnames[@]}"; do

        # Using Hostname Array, pull Workload HREF from either hostname OR address (dependent on Nessus target(s))
        output=$(curl -s -k -X GET https://$pce_url/api/v2/orgs/$org_id/workloads -u $ilo_api:$ilo_secret | jq -r --arg hostname "$hostname" '.[] | select(.hostname == $hostname or .interfaces[].address == $hostname) | .href')
        display_name=$(curl -s -k -X GET https://$pce_url/api/v2/orgs/$org_id/workloads -u $ilo_api:$ilo_secret | jq -r --arg hostname "$hostname" '.[] | select(.hostname == $hostname or .interfaces[].address == $hostname) | .hostname')
        IFS=$'\n' read -r -d '' -a workloads <<< "$output"

        # Retrieve existing labels from workload
        current_labels=$(curl -s -k -X GET https://$pce_url/api/v2$workloads -u $ilo_api:$ilo_secret | jq '. | .labels | map({ href: .href})')

        # Append new 'Risky' Label to JSON Body
        new_entry='{"href":'$label'}'
        updated_array=$(echo "$current_labels" | jq --argjson new_entry "$new_entry" '. += [$new_entry] | { "labels": .}')

        # Update workload with new Label
        curl -s -k -X PUT https://$pce_url/api/v2$workloads -u $ilo_api:$ilo_secret -H "Content-Type: application/json" -d "$updated_array"
        echo "Applying 'Risky' label to workload: $display_name"

    done

  done

else

  echo "Invalid selection. Please enter a valid number..."

fi
