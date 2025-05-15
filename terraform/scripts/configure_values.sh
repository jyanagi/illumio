#!/bin/bash
# Remove Old Values File
rm -rf illumio-values.yaml

# PCE Credentials
RAW_URL=$(terraform output -raw tf_pce_url)
PCE_URL=${RAW_URL#https://}
PCE_ORG_ID=$(terraform output -raw tf_pce_org_id)
PCE_API_KEY=$(terraform output -raw tf_pce_api_key)
PCE_API_SECRET=$(terraform output -raw tf_pce_api_secret)

# Pairing Profile Information
PCE_PP_HREF=$(terraform output -raw tf_k8s_pp)
PCE_PP_KEY=$(curl -s -k -X POST https://$PCE_URL/api/v2$PCE_PP_HREF/pairing_key -u $PCE_API_KEY:$PCE_API_SECRET -H 'Content-Type: application/json' -d "{}" | jq -r '.activation_code' | tr -d '"')

# Container Cluster Information
CLUSTER_ID=$(terraform output -raw tf_k3s_cc_id)
CLUSTER_TOKEN=$(terraform output -raw tf_k3s_cc_token)

# Runtime Information
clear
runtimes=("containerd" "docker" "crio" "k3s_containerd")
echo ""
echo "-------------------------------------------------"
echo ""
echo "Select the appropriate container runtime:"

for i in "${!runtimes[@]}"; do
  echo "$((i+1)). ${runtimes[$i]}"
done
echo ""
echo "-------------------------------------------------"
echo ""
read -p "Enter number [default: containerd]: " selection
echo ""
echo "-------------------------------------------------"
echo ""
if [[ -z "$selection" || ! "$selection" =~ ^[1-4]$ ]]; then
  RUNTIME="${runtimes[0]}"
else
  RUNTIME="${runtimes[$((selection-1))]}"
fi
# Container Manager Information

clear
managers=("kubernetes" "openshift")
echo ""
echo "-------------------------------------------------"
echo ""
echo "Select the appropriate container manager:"
for i in "${!managers[@]}"; do
  echo "$((i+1)). ${managers[$i]}"
done
echo ""
echo "-------------------------------------------------"
echo ""
read -p "Enter number [default: kubernetes]: " selection
echo ""
echo "-------------------------------------------------"
echo ""
if [[ -z "$selection" || ! "$selection" =~ ^[1-2]$ ]]; then
  MANAGER="${managers[0]}"
else
  MANAGER="${managers[$((selection-1))]}"
fi
# Network Type Information
clear
networktypes=("overlay" "flat")
echo ""
echo "-------------------------------------------------"
echo ""
echo "Select the appropriate network type:"

for i in "${!networktypes[@]}"; do
  echo "$((i+1)). ${networktypes[$i]}"
done
echo ""
echo "-------------------------------------------------"
echo ""
read -p "Enter number [default: overlay]: " selection
echo ""
echo "-------------------------------------------------"
echo ""

if [[ -z "$selection" || ! "$selection" =~ ^[1-2]$ ]]; then
  NETWORKTYPE="${networktypes[0]}"
else
  NETWORKTYPE="${networktypes[$((selection-1))]}"
fi

# CLAS Architecture Information
clear
echo ""
read -p "Enable CLAS architecture? (yes/no): " response
echo ""

if [[ "$response" =~ ^[Yy]([Ee][Ss])?$ ]]; then
  CLUSTER_MODE="clusterMode: clas"
else
  ""
fi
clear

cat << EOF > illumio-values.yaml
pce_url: $PCE_URL
cluster_id: $CLUSTER_ID
cluster_token: $CLUSTER_TOKEN
cluster_code: $PCE_PP_KEY # Pairing Profile
containerRuntime: $RUNTIME # supported values: [containerd (default), docker, crio, k3s_containerd]
containerManager: $MANAGER # supported values: [kubernetes, openshift]
networkType: $NETWORKTYPE  # CNI type, allowed values are [overlay, flat]
$CLUSTER_MODE

# Uncomment if using Private CA
# Must create a configmap labeled 'private-ca' referencing the private CA certificate
# Example:  kubectl -n illumio-system create configmap private-ca --from-file=private-ca.crt
#extraVolumes:
#  - name: private-ca
#    configMap:
#      name: private-ca
#extraVolumeMounts:
#  - name: private-ca
#    mountPath: /etc/pki/tls/ilo_certs/
#    readOnly: false
#ignore_cert: true

storage:
  registry: "docker.io/bitnami"
  repo: "etcd"
  imageTag: "3.5.7"
  imagePullPolicy: "IfNotPresent"
  sizeGi: 1
EOF


