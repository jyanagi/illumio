# PCE Credentials
RAW_URL=$(terraform output -raw tf_pce_url)
PCE_URL=${RAW_URL#https://}
PCE_ORG_ID=$(terraform output -raw tf_pce_org_id)
PCE_API_KEY=$(terraform output -raw tf_pce_api_key)
PCE_API_SECRET=$(terraform output -raw tf_pce_api_secret)

TF_LABEL_LOC=$(terraform output -raw tf_label_loc)
TF_LABEL_ENV=$(terraform output -raw tf_label_env)
TF_LABEL_APP=$(terraform output -raw tf_label_app)

# Pull Current Firewall Coexistence Scopes and Append New Scopes Using TF HREFs
UPDATED_PAYLOAD=$(curl -sX GET "https://$PCE_URL/api/v2/orgs/$PCE_ORG_ID/sec_policy/draft/firewall_settings" \
  -u "$PCE_API_KEY:$PCE_API_SECRET" \
  -H 'Accept: application/json' | \
  jq --arg TF_LABEL_LOC "$TF_LABEL_LOC" \
     --arg TF_LABEL_ENV "$TF_LABEL_ENV" \
     --arg TF_LABEL_APP "$TF_LABEL_APP" \
     '{
       firewall_coexistence: (.firewall_coexistence + [
         {
           "illumio_primary": true,
           "scope": [
             { "href": $TF_LABEL_LOC },
             { "href": $TF_LABEL_ENV },
             { "href": $TF_LABEL_APP }
           ]
         }
       ])
     }')

curl -sX PUT "https://$PCE_URL/api/v2/orgs/$PCE_ORG_ID/sec_policy/draft/firewall_settings" \
  -u "$PCE_API_KEY:$PCE_API_SECRET" \
  -H 'Content-Type: application/json' \
  -d "$UPDATED_PAYLOAD"

# Provision the Security Policy
curl -sX POST "https://$PCE_URL/api/v2/orgs/$PCE_ORG_ID/sec_policy" \
  -u "$PCE_API_KEY:$PCE_API_SECRET" \
  -H 'Content-Type: application/json' \
  -d '{}'
