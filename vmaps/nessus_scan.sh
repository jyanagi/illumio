#!/bin/bash

# Use External Credentials File

source .credentials

# Clear Screen

clear

# Download CISA Known Exploited Vulnerabilities Database

wget -N https://www.cisa.gov/sites/default/files/csv/known_exploited_vulnerabilities.csv

# Create New Label Dimension labeled "High Risk"

label_dimension=$(
	curl -s -k -X GET https://$pce_url/api/v2/orgs/$org_id/label_dimensions \
	-u $ilo_api:$ilo_secret \
	-H "Accept: application/json" \
	| jq -r '.[] | .display_name' >/dev/null 2>&1)

if $label_dimension | grep -q "Risk Level"; then
	
	label=$(
	curl -s -k -X GET https://$pce_url/api/v2/orgs/$org_id/labels \
		-u $ilo_api:$ilo_secret \
		-H "Accept: application/json" \
		| jq '.[] | select(.value == "High Risk") | .href')
else

	curl -s -k -X POST "https://$pce_url/api/v2/orgs/$org_id/label_dimensions" \
		-u "$ilo_api:$ilo_secret" \
		-H "Content-Type: application/json" \
		-d '{
		"key": "risk_level",
		"display_name": "Risk Level",
		"display_info": {
			"icon": "critical",
			"initial": "RL",
			"background_color": "#ff0000",
			"foreground_color": "#ffffff",
			"display_name_plural": "Risk Level"
			}
		}' >/dev/null 2>&1

	curl -s -k -X POST https://$pce_url/api/v2/orgs/$org_id/labels \
		-u $ilo_api:$ilo_secret \
		-H "Content-Type: application/json" \
		-d '{
			"key":"risk_level",
			"value":"High Risk"
		}' >/dev/null 2>&1

	label=$(
	curl -s -k -X GET https://$pce_url/api/v2/orgs/$org_id/labels \
		-u $ilo_api:$ilo_secret \
		| jq '.[] | select(.value == "High Risk") | .href')

fi

# List Scans

readarray -t scans < <(curl -s -k -X GET "https://$nessus_url/scans" \
	-H "X-ApiKeys: accessKey=$access_key; secretKey=$secret_key" \
	-H "Content-Type: application/json" \
	| jq -r '.scans[].name')

# Convert Output of Scans to an Array

echo ""
echo "-----------------------------------------------------------------------"
echo " Select the Nessus Scan you would like to parse:                       "
echo "-----------------------------------------------------------------------"
echo ""

# Print Array as Itemized/Numbered List

for i in "${!scans[@]}"; do
	echo "$((i+1)). ${scans[i]}"
done

# Prompt User to Select Scan Number
echo ""
echo "-----------------------------------------------------------------------"
read -p " Enter the number of the scan you want to select (Ctrl+C to cancel): " selection
echo "-----------------------------------------------------------------------"
echo ""

if [[ $selection =~ ^[0-9]+$ && $selection -ge 1 && $selection -le ${#scans[@]} ]]; then

	# Scan Selection
	selected_scan="${scans[selection-1]}"
	scan_id=$(
	curl -s -k -X GET https://$nessus_url/scans \
		-H "X-ApiKeys: accessKey=$access_key; secretKey=$secret_key" \
		| jq -r --arg selected_scan "$selected_scan" '.scans[] | select(.name == $selected_scan) | .id' )

	echo -e "\e[1;33mYou selected: $selected_scan (Scan ID: $scan_id)\e[0m"

	# Generate a Report

	file_id=$(
	curl -s -k -X POST https://$nessus_url/scans/$scan_id/export \
		-H "X-ApiKeys: accessKey=$access_key; secretKey=$secret_key" \
		-H "Content-Type: application/json" \
		-d '{
			"format": "csv"
		}' \
		| jq -r '.file | @text')

	echo -e "\e[1;33mGenerating Vulnerability Report (File ID: $file_id)...\e[0m"

# Check Status of the Report

while true; do

	status=$(
	curl -s -k -X GET https://$nessus_url/scans/$scan_id/export/$file_id/status \
	-H "X-ApiKeys: accessKey=$access_key; secretKey=$secret_key" \
	-H "Content-Type: application/json" \
	| jq -r '.status')
	
	echo -e "\e[1;34mReport Generation Status: $status\e[0m"

	if [[ "$status" == "ready" ]]; then
		echo -e "\e[1;33mNessus Scan Export is ready! Downloading report...\e[0m"

		curl -s -k -X GET https://$nessus_url/scans/$scan_id/export/$file_id/download \
			-H "X-ApiKeys: accessKey=$access_key; secretKey=$secret_key" \
			-H "Content-Type: application/json" \
			-o report.csv 

		echo -e "\e[1;32mReport Download Complete!\e[0m"

		break
	fi

	sleep 5
done

# Parse Known Exploited Vulnerabilities data against Vulnerability Scan Report and output as .JSON

python3 <<EOF

import csv
import json

def cross_reference_cves(kev_file, report_file, output_json):
	kev_cves = set()
	with open(kev_file, "r", encoding="utf-8") as kev_f:
		reader = csv.reader(kev_f)
		next(reader)  # Skip header
		for row in reader:
			if len(row) >= 9 and row[8].strip() == "Known":
				kev_cves.add(row[0].strip())

	cve_host_mapping = []
	with open(report_file, "r", encoding="utf-8") as report_f:
		reader = csv.reader(report_f)
		next(reader)  # Skip header
		for row in reader:
			if len(row) >= 5:
				cve = row[1].strip()
				host = row[4].strip()
			if cve in kev_cves and cve and host:
				entry = next((item for item in cve_host_mapping if item["CVE"] == cve), None)
				if entry:
        			        entry["Host"].append(host)
				else:
		        		cve_host_mapping.append({"CVE": cve, "Host": [host]})

	with open(output_json, "w", encoding="utf-8") as json_f:
        	json.dump(cve_host_mapping, json_f, indent=4)

cross_reference_cves("known_exploited_vulnerabilities.csv", "report.csv", "cve_host_mapping.json")

EOF

json_file=cve_host_mapping.json
readarray -t CVEs < <(jq -r '.[].CVE' $json_file)

known_vulns=$(awk -F ',' '$9=="Known" {print $1}' known_exploited_vulnerabilities.csv)
num_vulns=$(grep -w "Known" known_exploited_vulnerabilities.csv | wc -l)

echo ""
echo "-----------------------------------------------------------------------"
echo " Cross-referencing Nessus Vulnerability Scan results against           "
echo " CISA Known Exploited Vulnerabilities Database [$num_vulns CVEs]       "
echo "         								     "
echo " CVE(s) with Known Exploited Ransomware Campaign Use identified        "
echo " Applying 'High Risk' label to the following workload(s)               "
echo "-----------------------------------------------------------------------"

# Gather Hostnames from Scan Report

readarray -t unique_hosts < <(jq -r '[.[] | .Host[]] | unique | .[] | split(".") | first | @text' "$json_file")

for hostname in "${unique_hosts[@]}"; do
	hostname=$(echo "$hostname" | tr -d '[:space:]')

	# Check if hostname is empty
	if [[ -z "$hostname" ]]; then
		echo "Error: hostname variable is empty! Skipping..."
		continue
	else
		echo ""
		echo -e "\e[1;31mProcessing Host: \e[0m$hostname"
	        echo "..............................................................."
	fi

	wkld_href=$(curl -s -k -X GET "https://$pce_url/api/v2/orgs/$org_id/workloads" \
		-u $ilo_api:$ilo_secret \
		-H "Accept: application/json" \
		| jq -r --arg hostname "$hostname" '.[] | select(.hostname == $hostname or .interfaces[].address == $hostname) | .href')
		
	if [[ -z "$wkld_href" ]]; then
		echo "Error: No workload found for hostname: $hostname"
		continue
	fi
	
	# Retrieve existing labels from workload

	current_labels=$(curl -s -k -X GET "https://$pce_url/api/v2$wkld_href" \
		-u $ilo_api:$ilo_secret \
		-H "Accept: application/json" \
		| jq -c '. | .labels | map({ href: .href})' 2>/dev/null)

	# Append new 'High Risk' Label to JSON Body

	new_entry=$(jq -n --arg label "$label" '{"href":'$label'}' 2>/dev/null)
	updated_array=$(jq --argjson new_entry "$new_entry" '{"labels": (. + [$new_entry]) }' <<< "$current_labels" 2>/dev/null)

	#Update workload with new 'High Risk' Label
			
	curl -s -k -X PUT https://$pce_url/api/v2$wkld_href \
			-u $ilo_api:$ilo_secret \
			-H "Content-Type: application/json" \
			-d "$updated_array" >/dev/null 2>&1

	for cve in $CVEs; do

		# Gather Hostnames from Scan Report

                echo "Identified ($cve) on $hostname"

	done

done
echo ""
echo "-----------------------------------------------------------------------"
echo -e "\e[1;32mACTIONS COMPLETED: \e[0mApplied \e[1;31m'High Risk'\e[0m Label to \e[1m${#unique_hosts[@]} \e[0mworkloads"
echo "-----------------------------------------------------------------------"
echo ""

else
	echo ""
	echo "-----------------------------------------------------------------------"
	echo "Invalid selection. Please enter a valid option..."
	echo "-----------------------------------------------------------------------"
	echo ""

fi

# Perform Cleanup
rm -rf report.csv
rm -rf cve_host_mapping.json
rm -rf known_exploited_vulnerabilities.csv
