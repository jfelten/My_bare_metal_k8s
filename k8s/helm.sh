#!/bin/bash

kubectl create -f helm.yaml
kubectl delete deployment tiller-deploy --namespace=kube-system 
kubectl delete service tiller-deploy --namespace=kube-system 
rm -rf ~/.helm/


helm init --service-account helm
