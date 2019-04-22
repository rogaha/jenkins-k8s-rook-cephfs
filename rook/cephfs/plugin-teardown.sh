#!/bin/bash

deployment_base="${1}"

if [[ -z $deployment_base ]]; then
	deployment_base="kubernetes"
fi

cd "$deployment_base" || exit 1

objects=(csi-cephfsplugin-attacher csi-cephfsplugin-provisioner csi-cephfsplugin csi-attacher-rbac csi-provisioner-rbac csi-nodeplugin-rbac)

for obj in "${objects[@]}"; do
	kubectl delete -f "./$obj.yaml"
done
