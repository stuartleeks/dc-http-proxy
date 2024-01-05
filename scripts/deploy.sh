#!/bin/bash
set -e

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

if [[ -f "$script_dir/../.env" ]]; then
    echo "Loading .env"
    source "$script_dir/../.env"
fi

if [[ ${#BASENAME} -eq 0 ]]; then
  echo 'ERROR: Missing environment variable BASENAME' 1>&2
  exit 6
fi

if [[ ${#LOCATION} -eq 0 ]]; then
  echo 'ERROR: Missing environment variable LOCATION' 1>&2
  exit 6
fi

if [[ ${#DEFAULT_VM_PASSWORD} -eq 0 ]]; then
  echo 'ERROR: Missing environment variable DEFAULT_VM_PASSWORD' 1>&2
  exit 6
fi

if [[ -f ~/.ssh/azureuser ]]; then
  echo "~/.ssh/azureuser already exists - skipping" 1>&2
else
    echo "Creating ~/.ssh/azureuser"
    ssh-keygen \
        -m PEM \
        -t rsa \
        -b 4096 \
        -C "azureuser@myserver" \
        -f ~/.ssh/azureuser \
        -N ""
fi


RESOURCE_GROUP_NAME="$BASENAME"
echo "creating RG ($RESOURCE_GROUP_NAME, location $LOCATION)"
az group create --name "$RESOURCE_GROUP_NAME" --location "$LOCATION"
echo "done creating RG"

cat << EOF > "$script_dir/../infra/azuredeploy.parameters.json"
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "${LOCATION}"
    },
    "baseName": {
      "value": "${BASENAME}"
    },
    "defaultVmPassword": {
      "value": "${DEFAULT_VM_PASSWORD}"
    }
  }
}
EOF

deployment_name="deployment-${BASENAME}-${LOCATION}"
cd "$script_dir/../infra/"
echo "=="
echo "==Starting bicep deployment ($deployment_name)"
echo "=="
output=$(az deployment group create \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --template-file main.bicep \
  --name "$deployment_name" \
  --parameters azuredeploy.parameters.json \
  --output json)
echo "$output" | jq "[.properties.outputs | to_entries | .[] | {key:.key, value: .value.value}] | from_entries" > "$script_dir/../infra/output.json"


echo "Done."