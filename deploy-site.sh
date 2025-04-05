#!/bin/bash

# --- CONFIGURAZIONE ---
IMAGE_NAME="secondo-nginx"
BASE_TAG="v"
VERSION_TAG=$(date +%Y%m%d%H%M%S)
FULL_TAG="${BASE_TAG}${VERSION_TAG}"
TAR_FILE="${IMAGE_NAME}-${FULL_TAG}.tar"
DEPLOYMENT_FILE="nginx-deployment.yaml"
DEPLOYMENT_NAME="secondo-nginx-deployment"
NAMESPACE="default" # Puoi cambiare lo spazio dei nomi se necessario

# --- FUNZIONI ---

build_image() {
  echo "🛠️ Building container image with Podman..."
  podman build -t localhost/${IMAGE_NAME}:${FULL_TAG} .
  if [ $? -ne 0 ]; then
    echo "❌ Error building image."
    exit 1
  fi
  echo "✔️ Image built successfully: localhost/${IMAGE_NAME}:${FULL_TAG}"
}

save_image() {
  echo "💾 Saving container image to tar file: ${TAR_FILE}"
  podman save --format oci-archive -o "${TAR_FILE}" localhost/${IMAGE_NAME}:${FULL_TAG}
  if [ $? -ne 0 ]; then
    echo "❌ Error saving image."
    exit 1
  fi
  echo "✔️ Image saved successfully."
}

load_image_to_microk8s() {
  echo "📦 Loading container image to MicroK8s..."
  # Assicurati che il file tar sia accessibile al nodo MicroK8s
  # Se stai lavorando sulla stessa macchina, dovrebbe andare bene.
  microk8s ctr image import "${TAR_FILE}"
  if [ $? -ne 0 ]; then
    echo "❌ Error loading image to MicroK8s."
    echo "   Assicurati che MicroK8s sia in esecuzione e che il comando sia eseguito con sudo."
    exit 1
  fi
  echo "✔️ Image loaded to MicroK8s successfully."
}

apply_deployment() {
  echo "🚀 Applying Kubernetes Deployment from ${DEPLOYMENT_FILE}..."
  # Sostituiamo il tag dell'immagine nel file YAML con la nuova versione
  sed -i "s#image: localhost/${IMAGE_NAME}:.*#image: localhost/${IMAGE_NAME}:${FULL_TAG}#" "${DEPLOYMENT_FILE}"
  if [ $? -ne 0 ]; then
    echo "❌ Error updating image tag in Deployment file."
    exit 1
  fi
  microk8s kubectl apply -n "${NAMESPACE}" -f "${DEPLOYMENT_FILE}"
  if [ $? -ne 0 ]; then
    echo "❌ Error applying Deployment."
    exit 1
  fi
  echo "✔️ Deployment applied successfully: ${DEPLOYMENT_NAME} in namespace ${NAMESPACE}."
}

# --- MAIN SCRIPT ---

# Assicurati di essere nella directory con il Dockerfile e i file del sito
if [ ! -f Dockerfile ]; then
  echo "❌ Dockerfile not found in the current directory."
  exit 1
fi

build_image
save_image
load_image_to_microk8s
apply_deployment

echo "✅ Deployment process completed. Check the status with 'microk8s kubectl get pods' or 'k9s'."

exit 0
