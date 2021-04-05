#!/bin/bash

usage () {
    echo "Usage: ./gen-iso.sh [--ssh-pub-key SSH_KEY]"
    echo "  --ssh-pub-key            Path to public key to be added as an authorized key for `clusteruser`"
    echo "  -h, --help               Prints usage"
  }

  while [[ "$#" -gt 0 ]]
do
  case $1 in
    --ssh-private-key)
      ssh_private=$2
      shift 2
      ;;
    --ssh-pub-key)
      ssh_path=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit
      ;;
  esac
done

mkdir output

config=./config.json
echo "Loading config from $config"

gateway=$(jq -r ".gateway" $config)
dnsserver=$(jq -r ".dnsserver" $config)

nodes=$(cat $config | jq ".nodes | length")
echo "Creating ${nodes} .iso files"

for (( node=0; node < $nodes; node++ ))
do
  mkdir cloud-data
  cp cloud-data-template/* ./cloud-data/

  name=$(jq -r ".nodes[$node].name" $config)
  echo "...Node $node: $name"

  vmIP=$(jq -r ".nodes[$node].vmIP" $config)
  base64_key=$(cat $ssh_private | base64 | tr -d '\n')
  pub_key=$(cat $ssh_path | cut -d" " -f1-2)

  # Modify cloud-data files
  sed -i "s%_PRIVATE_SSH_KEY_%${base64_key}%g" ./cloud-data/main-data.yaml
  sed -i "s%_CLUSTERUSER_KEY_%${pub_key}%g" ./cloud-data/main-data.yaml
  sed -i "s%_CLUSTERUSER_KEY_%${pub_key}%g" ./cloud-data/user-data.yaml
  sed -i "s%_HOSTNAME_%${name}%g" ./cloud-data/meta-data.yaml
  sed -i "s%_GATEWAY_%${gateway}%g" ./cloud-data/network-config.yaml
  sed -i "s%_DNS_SERVER_%${dnsserver}%g" ./cloud-data/network-config.yaml    
  sed -i "s%_IP_ADDRESSES_%${vmIP}%g" ./cloud-data/network-config.yaml

  # Create ISO file
  if [ $name = 'main' ]; then
    cloud-localds ./output/$name.iso ./cloud-data/main-data.yaml ./cloud-data/meta-data.yaml -N ./cloud-data/network-config.yaml
  else
    cloud-localds ./output/$name.iso ./cloud-data/user-data.yaml ./cloud-data/meta-data.yaml -N ./cloud-data/network-config.yaml
  fi

  # Cleanup for next node
  rm cloud-data -r
done

