# PCE Credentials
RAW_URL=$(terraform output -raw tf_pce_url)
PCE_URL=${RAW_URL#https://}
PCE_ORG_ID=$(terraform output -raw tf_pce_org_id)
PCE_API_KEY=$(terraform output -raw tf_pce_api_key)
PCE_API_SECRET=$(terraform output -raw tf_pce_api_secret)

CC_ID=$(terraform output -raw tf_k3s_cc_id)

TF_LOC_LABEL=$(terraform output -raw tf_label_loc)
TF_ENV_LABEL=$(terraform output -raw tf_label_env)
TF_APP_LABEL=$(terraform output -raw tf_label_k8s_app)

#NAMESPACE="guestbook"
clear
echo ""
read -p "Enter k8s namespace to configure Illumio's Container Cluster Workload Profile for: " NAMESPACE
echo ""
clear

CC_HREF=$(curl -sX GET "https://$PCE_URL/api/v2/orgs/$PCE_ORG_ID/container_clusters/$CC_ID/container_workload_profiles" \
  -u "$PCE_API_KEY":"$PCE_API_SECRET" \
  -H 'Accept: application/json' \
  | jq -r --arg NAMESPACE "$NAMESPACE" '.[] | select(.namespace == $NAMESPACE) | .href')

BODY=$(jq -n \
  --arg LOC_LABEL "$TF_LOC_LABEL" \
  --arg ENV_LABEL "$TF_ENV_LABEL" \
  --arg APP_LABEL "$TF_APP_LABEL" \
  '{
    labels: [
      { key: "loc", assignment: { href: $LOC_LABEL } },
      { key: "env", assignment: { href: $ENV_LABEL } },
      { key: "app", assignment: { href: $APP_LABEL } }
    ],
    enforcement_mode: "visibility_only",
    managed: true
  }')

curl -sX PUT "https://$PCE_URL/api/v2$CC_HREF" \
  -u "$PCE_API_KEY":"$PCE_API_SECRET" \
  -H 'Content-Type: application/json' \
  -d "$BODY"

echo ""
echo "Container Cluster Workload Profile successfully configured for '$NAMESPACE'"
echo ""
