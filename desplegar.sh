#!/usr/bin/env bash
# Levanta todo desde cero en el orden correcto.
# Problema: los servicios de Cloud Run necesitan que las imagenes existan,
# y las imagenes necesitan que exista el registro. Por eso son tres pasos.
set -euo pipefail
cd "$(dirname "$0")"

# Toma la etiqueta de la imagen desde terraform.tfvars (ej. v2).
ETIQUETA=$(grep imagen_backend infra/terraform.tfvars | sed -E 's/.*:([^"]+)".*/\1/')

echo "== 1. Cimientos: APIs y registro (Terraform)"
terraform -chdir=infra init -input=false
terraform -chdir=infra apply -auto-approve \
  -target=google_artifact_registry_repository.imagenes

echo "== 2. Imagenes con la etiqueta $ETIQUETA (Docker)"
RUTA=$(terraform -chdir=infra output -raw ruta_registro)
REGION=$(echo "$RUTA" | cut -d/ -f1)
gcloud auth configure-docker "$REGION" --quiet
docker build -t "$RUTA/backend:$ETIQUETA" backend
docker build -t "$RUTA/frontend:$ETIQUETA" frontend
for imagen in backend frontend; do
  for intento in 1 2 3 4 5; do
    docker push "$RUTA/$imagen:$ETIQUETA" && break
    echo "push de $imagen fallo, reintento $intento"; sleep 10
  done
done

echo "== 3. Todo lo demas: base, identidades y servicios (Terraform)"
terraform -chdir=infra apply -auto-approve

echo "== Listo"
terraform -chdir=infra output
