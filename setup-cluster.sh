#!/bin/bash

source ./set-env.sh

echo "Creating new cluster '${CLUSTER}'..."
gcloud container clusters create "${CLUSTER}" --zone "${ZONE}"
# Set auth on kubectl
gcloud container clusters get-credentials "${CLUSTER}" --zone "${ZONE}"

echo "Deploying Redis..."
# Possible parameters: https://github.com/helm/charts/tree/master/stable/redis
helm install redis \
  --set usePassword=false \
    stable/redis

echo "Deploying RabbitMQ with AMQP 1.0 plugin..."
# Possible parameter: https://github.com/helm/charts/tree/master/stable/rabbitmq
helm install rabbitmq-amqp10 \
  --set rabbitmq.username=${RABBITMQ_USER},rabbitmq.password=${RABBITMQ_PASSWORD},rabbitmq.plugins="rabbitmq_management rabbitmq_peer_discovery_k8s rabbitmq_amqp1_0" \
  stable/rabbitmq

echo "Creating new Filestore '${FILESTORE_ID}'..."
gcloud filestore instances create ${FILESTORE_ID} \
    --project=${PROJECT_ID} \
    --zone=${ZONE} \
    --tier=STANDARD \
    --file-share=name="${FILESTORE_SHARE_NAME}",capacity=1TB \
    --network=name="default"


# Sometimes it takes a few seconds until the IP address is available
sleep 5

FILESTORE_IP=`gcloud filestore instances describe ${FILESTORE_ID} \
     --project=${PROJECT_ID} \
     --zone=${ZONE} \
     --format="value(networks.ipAddresses[0])"`
echo "Filestore IP: ${FILESTORE_IP}"

echo "Creating ConfigMap with platform services..."
echo "apiVersion: v1
kind: ConfigMap
metadata:
  name: platform-services
  namespace: default
data:
  REDIS_HOST: redis-master.default
  REDIS_PORT: \"6379\"
  RABBITMQ_HOST: rabbitmq-amqp10.default
  RABBITMQ_PORT: \"5672\"
  RABBITMQ_USER: $RABBITMQ_USER" \
  | kubectl apply -f -


echo "Creating nfs Storage Class with ReadWriteMany capability..."
echo "apiVersion: v1
kind: PersistentVolume
metadata:
    name: nfs-filestore
    namespace: default
spec:
    storageClassName: nfs
    capacity:
        storage: 1T
    accessModes:
        - ReadWriteMany
    nfs:
        path: /$FILESTORE_SHARE_NAME
        server: $FILESTORE_IP"\
  | kubectl apply -f -

echo "Successfully setup cluster!"
