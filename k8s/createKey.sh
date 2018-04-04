#!/bin/bash

if [ $# -ne 1 ]
then
  echo "Usage: $0 <CLIENT_KEY_NAME>"
  exit
fi

KEY_NAME=$1
NAMESPACE=$(kubectl get pods --all-namespaces -l type=openvpn -o jsonpath='{.items[0].metadata.namespace}')
POD_NAME=$(kubectl get pods -n $NAMESPACE -l type=openvpn -o jsonpath='{.items[0].metadata.name}')
SERVICE_NAME=$(kubectl get svc -n $NAMESPACE -l type=openvpn  -o jsonpath='{.items[0].metadata.name}')
SERVICE_IP=cottagetech.sytes.net
kubectl -n $NAMESPACE exec -it $POD_NAME /etc/openvpn/setup/newClientCert.sh $KEY_NAME $SERVICE_IP
kubectl -n $NAMESPACE exec -it $POD_NAME cat /etc/openvpn/certs/pki/$KEY_NAME.ovpn > tmp.ovpn

sed "s/<\/connection>/${SERVICE_IP} 30000 tcp<\/connection>/g" tmp.ovpn > $KEY_NAME.ovpn
rm tmp.ovpn