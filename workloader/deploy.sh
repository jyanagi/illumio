# Start recording the time
start_time=$(date +%s)

# Your script commands here
echo "Deploying Tenant Environments..."

file=/home/ec2-user/scripts/.curdz

read -p "What is the FIRST tenant that you would like to deploy? [1-20]: " x
read -p "What is the LAST tenant that you would like to deploy? [1-20]: " y

for ((i = x; i <= y; i++)); do

        login="admin@illumio-$i.lab"
        tenant="illumio-$i.lab"
        line=$(grep "$login" $file)
        dir="/replace/with/your/directory/illumio-$i.lab"
        base_url="illumio.acme.com:8443"
        
        ip_lists=iplists.csv
        label_dimension=label-dimensions.csv
        processes_file=processes.csv
        traffic_file=traffic.csv
        ven_file=vens.csv
        workload_file=wklds.csv

        if [ -n "$line" ]; then

                # Define Variables for Tenant Information
                org_id=$(echo "$line" | cut -d',' -f3)
                users_href=$(echo "$line" | cut -d',' -f4)
                api_user=$(echo "$line" | cut -d',' -f5)
                api_secret=$(echo "$line" | cut -d',' -f6)

                ### Begin PCE Pairing Profile Activities

                # Retrieve the Pairing Profile HREF value (required for key generation )
                endpoint_pp=$(curl -k -s -X GET https://$base_url/api/v2/orgs/$org_id/pairing_profiles -u $api_user:$api_secret | jq '.[] | select(.name == "Default (Endpoints)") | .href' | tr -d '"')
                server_pp=$(curl -k -s -X GET https://$base_url/api/v2/orgs/$org_id/pairing_profiles -u $api_user:$api_secret | jq '.[] | select(.name == "Default (Servers)") | .href' | tr -d '"')

                # Retrieve the Server and Endpoint Activation Keys ( used for VEN pairing/activation )
                endpoint_key=$(curl -k -s -X POST https://$base_url/api/v2$endpoint_pp/pairing_key -u $api_user:$api_secret -H 'Content-Type: application/json' -d "{}" | jq -r '.activation_code' | tr -d '"')
                server_key=$(curl -k -s -X POST https://$base_url/api/v2$server_pp/pairing_key -u $api_user:$api_secret -H 'Content-Type: application/json' -d "{}" | jq -r '.activation_code' | tr -d '"')

                ### End PCE Pairing Profile Activities

                ### Begin VENSIM Activities
                step1_start=$(date +%s)
                echo "Deploying and Activating VENs for $tenant..."
                cd $dir && vensim activate -c $ven_file -p $processes_file -m $base_url -a $server_key -e $endpoint_key
                step1_end=$(date +%s)
                step1_elapsed=$((step1_end - step1_start))
                echo "Completion time: $step1_elapsed"

                # Import Label Dimensions
                step2_start=$(date +%s)
                echo "Configuring Label Dimensions for $tenant...."
                workloader label-dimension-import $label_dimension --update-pce --no-prompt
                step2_end=$(date +%s)
                step2_elapsed=$((step2_end - step2_start))
                echo "Completion time: $step2_elapsed"

                # Label VENs and Unmanaged Workloads
                step3_start=$(date +%s)
                echo "Labeling VENs & Workloads for $tenant......."
                workloader wkld-import $workload_file --umwl --update-pce --no-prompt
                step3_end=$(date +%s)
                step3_elapsed=$((step3_end - step3_start))
                echo "Completion time: $step3_elapsed"

                # Import IP Lists
                step4_start=$(date +%s)
                echo "Importing IP Lists for $tenant.............."
                workloader ipl-import $ip_lists --update-pce --no-prompt --provision
                step4_end=$(date +%s)
                step4_elapsed=$((step4_end - step4_start))
                echo "Completion time: $step4_elapsed"

                # Import and Post Traffic
                step5_start=$(date +%s)
                echo "Posting Traffic for $tenant................."
                vensim post-traffic -c $ven_file -t $traffic_file -d today
                step5_end=$(date +%s)
                step5_elapsed=$((step5_end - step5_start))
                echo "Completion time: $step5_elapsed"  
        
                echo "Tenant '$tenant' is deployed..."
                
                ### End VENSIM Activities       

        fi
done

# End recording the time
end_time=$(date +%s)

# Calculate the elapsed time
elapsed_time=$((end_time - start_time))

# Write the elapsed time to a file
echo "Deployment complete..."
echo "Elapsed time: $elapsed_time seconds"
