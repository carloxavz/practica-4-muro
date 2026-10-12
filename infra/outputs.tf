output "ruta_registro" {
  value = "${var.region}-docker.pkg.dev/${var.proyecto}/${google_artifact_registry_repository.imagenes.repository_id}"
}
output "url_backend" {
  value = google_cloud_run_v2_service.backend.uri
}
# La URL determinista es la que el backend acepta en CORS: abre el muro con esta.
output "url_frontend" {
  value = local.url_frontend
}

# La misma pagina con la URL antigua de Cloud Run. Sirve para probar el bloqueo de CORS:
# abierta desde aqui, el navegador rechaza las respuestas del backend.
output "url_frontend_alterna" {
  value = google_cloud_run_v2_service.frontend.uri
}
