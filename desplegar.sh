#!/usr/bin/env bash
# Levanta todo desde cero en el orden correcto.
# Problema: los servicios de Cloud Run necesitan que las imagenes existan,
# y las imagenes necesitan que exista el registro. Por eso son tres pasos.
set -euo pipefail
cd "$(dirname "$0")"

# Toma la etiqueta de la imagen desde terraform.tfvars (ej. v2).
ETIQUETA=$(grep imagen_backend infra/terraform.tfvars | sed -E 's/.*:([^"]+)".*/\1/')

echo "== 1. Cimientos: APIs, registro y permisos de Cloud Build (Terraform)"
terraform -chdir=infra init -input=false
terraform -chdir=infra apply -auto-approve \
  -target=google_artifact_registry_repository.imagenes \
  -target=google_project_iam_member.build

echo "== 2. Imagenes con la etiqueta $ETIQUETA (Cloud Build)"
# Cloud Build construye y sube desde la red de Google, sin depender del docker push
# de Cloud Shell. Los reintentos cubren el minuto que tardan los permisos recien dados.
RUTA=$(terraform -chdir=infra output -raw ruta_registro)
for imagen in backend frontend; do
  for intento in 1 2 3 4 5; do
    if gcloud builds submit "$imagen" --tag "$RUTA/$imagen:$ETIQUETA"; then
      break
    fi
    if [ "$intento" -eq 5 ]; then
      echo "no se pudo construir $imagen"; exit 1
    fi
    echo "build de $imagen fallo, reintento $intento"; sleep 30
  done
done

echo "== 3. Todo lo demas: base, identidades y servicios (Terraform)"
terraform -chdir=infra apply -auto-approve

echo "== Listo"
terraform -chdir=infra output
