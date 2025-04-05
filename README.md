```markdown
# Deploy Automatico di un Sito Web con Podman e MicroK8s

Questo documento descrive i passaggi per automatizzare la creazione e il deploy di un sito web (in questo caso, un server Nginx che serve contenuti statici) utilizzando Podman per la gestione dei container e MicroK8s come ambiente Kubernetes locale. Il processo è automatizzato tramite uno script Bash.

## Prerequisiti

* **Sistema Operativo:** Un sistema Linux (i comandi potrebbero variare leggermente su altre piattaforme).
* **Connessione Internet:** Necessaria per scaricare Podman, MicroK8s e le immagini container.
* **VMware (se applicabile):** Se stai eseguendo MicroK8s all'interno di una macchina virtuale VMware, assicurati che la rete sia configurata correttamente per l'accesso dall'host.

## Passaggi

### 1. Installazione di Podman

Podman è uno strumento per eseguire container OCI (Open Container Initiative) su sistemi Linux. Non richiede un daemon in background per funzionare.

```bash
# Esempio per sistemi basati su Debian/Ubuntu
sudo apt update
sudo apt install -y podman

# Esempio per sistemi basati su Fedora/CentOS/RHEL
sudo dnf install -y podman
```

Verifica l'installazione:

```bash
podman --version
```

### 2. Installazione di MicroK8s

MicroK8s è una distribuzione leggera e facile da installare di Kubernetes, fornita come snap package.

```bash
sudo snap install microk8s --classic --channel=1.29/stable # Sostituisci 1.29 con la versione stabile desiderata
```

Attendi il completamento dell'installazione. Una volta terminato, aggiungi il tuo utente al gruppo `microk8s` per evitare di dover usare `sudo` per alcuni comandi `kubectl`:

```bash
sudo usermod -aG microk8s $USER
newgrp microk8s
```

Verifica lo stato di MicroK8s:

```bash
microk8s status --wait-ready
```

Abilita i componenti necessari (se non sono già abilitati):

```bash
microk8s enable dns storage
```

Configura `kubectl` per interagire con il tuo cluster MicroK8s:

```bash
mkdir -p ~/.kube
sudo cp /var/snap/microk8s/current/credentials/client.config ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
```

Verifica l'installazione di `kubectl`:

```bash
kubectl version --client
kubectl get nodes
```

### 3. Creazione dei File del Sito Web e del `Dockerfile`

Nella directory del tuo progetto web, crea i file HTML, CSS, JavaScript, ecc. che compongono il tuo sito. Crea anche un file chiamato `Dockerfile` con le istruzioni per costruire l'immagine container Nginx.

**Esempio di `Dockerfile`:**

```dockerfile
FROM nginx:latest
COPY . /usr/share/nginx/html
```

Questo `Dockerfile` utilizza l'immagine ufficiale di Nginx e copia tutti i file dalla directory corrente all'interno della directory predefinita di Nginx per i contenuti web (`/usr/share/nginx/html`).

### 4. Creazione dello Script Bash per l'Autodeploy (`deploy-site.sh`)

Crea un file chiamato `deploy-site.sh` nella directory principale del tuo progetto (o in un percorso appropriato) con il seguente contenuto (adattalo alle tue esigenze):

```bash
#!/bin/bash

# --- CONFIGURAZIONE ---
IMAGE_NAME="secondo-nginx"
IMAGE_TAG=$(date +%Y%m%d%H%M%S)
FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
TAR_FILE="${IMAGE_NAME}-${IMAGE_TAG}.tar"
DEPLOYMENT_FILE="secondo-nginx-deployment.yaml"
SERVICE_FILE="secondo-nginx-service.yaml"
NAMESPACE="default"

# --- FUNZIONI ---

build_image() {
  echo "🛠️ Building container image with Podman..."
  podman build -t localhost/${FULL_IMAGE} .
  if [ $? -ne 0 ]; then
    echo "❌ Error building image."
    exit 1
  fi
  echo "✔️ Image built successfully: localhost/${FULL_IMAGE}"
}

save_image() {
  echo "💾 Saving container image to tar file: ${TAR_FILE}"
  podman save -o "${TAR_FILE}" localhost/${FULL_IMAGE}
  if [ $? -ne 0 ]; then
    echo "❌ Error saving image."
    exit 1
  fi
  echo "✔️ Image saved successfully."
}

load_image_to_microk8s() {
  echo "📦 Loading container image to MicroK8s..."
  sudo /snap/bin/microk8s ctr -n k8s.io image import "${TAR_FILE}"
  if [ $? -ne 0 ]; then
    echo "❌ Error loading image to MicroK8s."
    echo "   Assicurati che MicroK8s sia in esecuzione e che il comando sia eseguito con sudo."
    exit 1
  fi
  echo "✔️ Image loaded to MicroK8s successfully."
}

apply_deployment() {
  echo "🚀 Applying Kubernetes Deployment from ${DEPLOYMENT_FILE}..."
  microk8s kubectl apply -n "${NAMESPACE}" -f "${DEPLOYMENT_FILE}"
  if [ $? -ne 0 ]; then
    echo "❌ Error applying Deployment."
    exit 1
  fi
  echo "✔️ Deployment applied successfully."
}

apply_service() {
  echo "⚙️ Applying Kubernetes Service from ${SERVICE_FILE}..."
  microk8s kubectl apply -n "${NAMESPACE}" -f "${SERVICE_FILE}"
  if [ $? -ne 0 ]; then
    echo "❌ Error applying Service."
    exit 1
  fi
  echo "✔️ Service applied successfully."
}

# --- MAIN SCRIPT ---

set -e # Esci immediatamente se un comando fallisce

build_image
save_image
load_image_to_microk8s
apply_deployment
apply_service

echo "✅ Autodeploy completed!"

exit 0
```

Rendi lo script eseguibile:

```bash
chmod +x deploy-site.sh
```

### 5. Creazione dei File YAML di Kubernetes (`secondo-nginx-deployment.yaml` e `secondo-nginx-service.yaml`)

**`secondo-nginx-deployment.yaml`:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secondo-nginx-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: secondo-nginx
  template:
    metadata:
      labels:
        app: secondo-nginx
    spec:
      containers:
      - name: nginx
        image: localhost/secondo-nginx:latest # Il tag verrà aggiornato dallo script
        imagePullPolicy: IfNotPresent
        ports:
        - protocol: TCP
          containerPort: 80
```

**`secondo-nginx-service.yaml`:**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: secondo-nginx-service
spec:
  selector:
    app: secondo-nginx
  type: NodePort
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
      nodePort: 30080 # Scegli una porta NodePort libera (30000-32767)
```

### 6. Esecuzione dell'Autodeploy

Esegui lo script `deploy-site.sh` dalla directory principale del tuo progetto:

```bash
./deploy-site.sh
```

Questo script eseguirà i seguenti passaggi:

1.  Costruirà l'immagine container utilizzando Podman, taggandola con la data e l'ora correnti.
2.  Salverà l'immagine in un file `.tar`.
3.  Caricherà l'immagine in MicroK8s.
4.  Applicherà o aggiornerà il Deployment Kubernetes.
5.  Applicherà o aggiornerà il Servizio Kubernetes, esponendo il tuo sito web tramite una `NodePort`.

### 7. Accesso al Sito Web

Una volta completato l'autodeploy, puoi accedere al tuo sito web aprendo il browser e navigando all'indirizzo IP di uno dei tuoi nodi MicroK8s (solitamente `localhost` se MicroK8s è in esecuzione sulla tua macchina locale) seguito dalla `nodePort` specificata nel file `secondo-nginx-service.yaml` (nell'esempio, `30080`):

```
http://localhost:30080
```

## Aggiornamento del Sito Web

Per aggiornare il tuo sito web:

1.  Modifica i file HTML, CSS, JavaScript, ecc. nella directory del tuo progetto.
2.  Esegui nuovamente lo script `deploy-site.sh`:

    ```bash
    ./deploy-site.sh
    ```

Lo script ricostruirà una nuova immagine container con le tue modifiche, la caricherà in MicroK8s e aggiornerà il Deployment, rendendo le nuove modifiche visibili all'indirizzo IP e alla `NodePort` configurati.
