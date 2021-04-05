# Deploy a bare-metal cluster with a Custom VM Image on a Hyper-V enabled Windows Host with Ansible and kubeadm

This sample demonstrates how to leverage technologies like packer, cloud-init and ansible to easily configure a Kubernetes cluster at the edge on a Windows host.

Learn how to:

1. Build custom base images with Packer in an Azure VM
1. Configure images with cloud init
1. Automate kubernetes cluster configuration with Ansible and kubeadm

- [Prerequisites](#prerequisites)
- [Tech Stack](#tech-stack)
- [Getting Started](#getting-started)
  - [Custom Base Images](#custom-base-images)
  - [Creating the VMs](#creating-the-vms-on-hyper-v)
  - [Configuring K8s w/ Ansible](#configuring-kubernetes-with-ansible)
  - [Notes](#notes)
- [General Networking Notes](general-networking-notes)

## Prerequisites

- An azure subscription
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) (at least version 2.11.1)
- Windows with [Hyper-V enabled](https://docs.microsoft.com/en-us/virtualization/hyper-v-on-windows/quick-start/enable-hyper-v#:~:text=Enable%20the%20Hyper-V%20role%20through%20Settings%20%201,4%20Select%20Hyper-V%20and%20click%20OK.%20See%20More)
  > The commands in this sample should apply to: Windows 10, Windows Server 2016, Microsoft Hyper-V Server 2016, Windows Server 2019, Microsoft Hyper-V Server 2019
- Powershell
- [WSL](https://docs.microsoft.com/en-us/windows/wsl/install-win10)

## Tech Stack

- [Azure](https://azure.microsoft.com/en-us/overview/what-is-azure/) - We utilize an Azure VM to create a custom base image for our Kubernetes nodes
- [Packer](https://www.packer.io/docs) - Used to create the base image
- [Hyper-V](https://docs.microsoft.com/en-us/windows-server/virtualization/hyper-v/hyper-v-technology-overview) - The Kubernetes nodes are virtual machines running in hyper-v
- [Ansible](https://docs.ansible.com/) - Ansible is used to automate the configuration of the Kubernetes cluster
- [cloud-init](https://cloudinit.readthedocs.io/) - Used to configure images (Azure VM, custom image, vm at runtime)

## Getting Started

### Custom Base Images

Oftentimes in edge scenarios, there is a requirement to build a custom base image. This is because edge workloads typically run on various operating systems with varying specs. Here, we spin up a Linux VM in azure with preconfigured data in our cloud-init.yaml. 

The cloud-init.yaml specifies the packages we want to install on the azure vm and the files we want to be written on the vm. The files we expect to be on the vm are:

  1. `packer.json` configuration file to tell packer what our desired image should look like
  1. `cloud-data` folder with contents to configure the built image with a *packer* user which is necessary for packer to build the image successfully
  
  ```sh
  #
  # The following commands can be run either in Powershell or WSL
  #

  # Create VM in Azure where the base image will be built
  az group create -n $RG -l $LOCATION
  $VM_IP=$(az vm create -g $RG --name edgeSample-vm --image UbuntuLTS --admin-username azureuser --ssh-key-value ~/.ssh/id_rsa.pub --custom-data base-image/cloud-init.yaml --query "publicIpAddress" -o tsv)

  # Run build script (Note: this script was written onto the VM via cloud-init)
  ssh azureuser@$VM_IP sudo chmod +x ./build-image.sh && sudo ./build-image.sh

  # Copy zip to local
  scp azureuser@$VM_IP:/home/azureuser/baseimage.vhdx.zip sample/base-image
  ```

### Creating the VMs on Hyper-V

Once we have a base image, we need to spin up our virtual machines locally on Hyper-V

First, we'll generate our iso files to include data necessary for VM access and networking:

  ```bash
  #
  # Run the following commands in WSL
  #

  cd node-init

  # Create an SSH key without a passphrase
  ssh-keygen -q -m PEM -t rsa -b 4096 -f ./ansible_rsa
  
  ./gen-iso.sh --ssh-pub-key ansible_rsa.pub --ssh-private-key ansible_rsa
  ```

In the previous step, we included a `network-config.yaml` in our ISO files. This file is generated based off of the `config.json` file which specifies the network setup we expect on the corresponding VMs. All VMs will share the same gateway and public dns, and each will have a static IP: **172.17.1.100**, **172.17.1.101**, and **172.17.1.102**. Feel free to *change* these values if these IPs conflict with your network.

This next step we will setup the network and spin up our VMs. The following script will create an internal switch, assign an IP address space, and create a nat for our VMs. Then, it will create the VMs using the base image that is passed in as a parameter, attach the ISO, and start the VMs.

  ```powershell
  #
  # Run this script in an elevated (admin) Powershell console
  #

  .\start-node.ps1 -VHDX_Zip ..\base-image\baseimage.vhdx.zip
  ```

Now that we have our VMs up and running (it may take a couple minutes for them to be ready), we'll copy over our ansible artifacts:

  ```bash
  #
  # Run this command in either Powershell or WSL
  #

  scp -i ansible_rsa -r ..\cluster clusteruser@172.17.1.100:~/
  ```

### Configuring Kubernetes with Ansible

Log into the `main` node using the ssh-key you created in the first step:

  ```sh
  #
  # Run the following commands on the Windows Host to login to the main node
  #

  ssh -i ansible_rsa clusteruser@172.17.1.100
  ```

Install ansible and then run the ansible scripts. We could have baked ansible in the previous step, but to minimize the size of the base image, we'll install necessary components at runtime.:

  ```sh
  #
  # These commands are ran on the main node
  #

  sudo apt update && sudo apt install ansible

  cd cluster

  ansible-playbook -i inventory.yml K8S-VMSetup.yml
  ansible-playbook -i inventory.yml K8S-Setup.yml
  ```
  
You should now have a 3 node kubernetes cluster!

### Cleanup

Use the `cleanup.ps1` script to cleanup resources after you've had your fun:

  ```powershell
  #
  # Run this script in an elevated (admin) Powershell console
  # Note: Ommit the -Network flag if you'd like to keep the network resources around
  #

  .\cleanup.ps1 -Network
  ```

### Additional Considerations

- Load Balancer support - as you may notice, this sample as is does not support LoadBalancer service types. Load balancers are easily supported in cloud native clusters but not so much on the edge. [MetalLB in layer 2 mode](https://metallb.universe.tf/configuration/#layer-2-configuration) could be a solution.
- Hyper-V networking - This sample uses a single internal switch and a NAT to allow for outbound internet access.
- General Networking Considerations for Kubernetes Clusters at the Edge:
  - Enabling VM - VM communication. Necessary for Kuberenetes to function properly
  - Enabming management access to the VMs
  - Giving your nodes outbound internet access.
  - Deciding on the network overlay for your Kubernetes applications.
- The sample leverages Ansible to automate and manage the nodes in the kubernetes cluster. An alternative could be [Metal3](https://metal3.io/documentation.html):
  - Ansible provides an easy way to manage remote resources and therefore was a prime candidate to manage and join remote nodes to a kubernetes cluster. All you need is the ansible binary, running on a linux machine, and SSH on remote machines.
  - Metal3 takes a different approach to solve this problem by utlizing similar concepts to [cluster-api](https://cluster-api.sigs.k8s.io/). First, istantiate an ephermal cluster to provision and manage bare-metal clusters using native kubernetes objects.
