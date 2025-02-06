This script demonstrates 3rd Party Integration with Illumio PCE and Nessus Vulnerability Scanner (either Professional or Essentials)

Outcome of execution is to automatically label VENs/Managed Workloads as "High Risk" based on Nessus Vulnerability Scan AND CISA's Known Exploited Vulnerabilities list for ransomware attacks (https://www.cisa.gov/known-exploited-vulnerabilities-catalog)

There are two files that are included in this repository:
- .credentials
- nessus_scan.sh

The credentials file is where you will configure Illumio PCE and Nessus URLs along with the respective API user/access keys and tokens/secrets.

The nessus_scan.sh file is written in both BASH and Python (Python3 is required to execute) and will configure the following:
First, the script will create a new label-dimension (if it doesn't already exist) followed by a new label using that dimensional type.
- New Label Dimension (Risk Level)
- New Label (High Risk) with a label type (Risk Level)

Second, the script will download and parse the CISA's Known Exploited Vulnerability (KEV) list and extract all CVEs of "Known" ransomware use.

Third, the script will allow you to select a scan, generate a report, and query the report against CISA's KEV and identify if there are any workloads that have any of these associated vulnerabilities and place them in an array (unique_hosts)

Fourth, the script will then parse this array and apply the new "High Risk" label to all workloads that match.

The outcome of this script is to demonstrate how you can integrate third-party security solutions, such as vulnerability scanners, to influence and enforce adaptive and dynamic secutiy policies based on context, rather than static, network-centric constructs.




