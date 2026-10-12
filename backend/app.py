# API del muro de mensajes (v2): listar, publicar y reaccionar, guardando en Firestore.
import os, uuid
from flask import Flask, request, jsonify
from google.cloud import firestore

app = Flask(__name__)
db = firestore.Client(database=os.environ.get("BASE_DATOS", "(default)"))
INSTANCIA = uuid.uuid4().hex[:6]

# Documento contador: cambia cada vez que el muro cambia (mensaje nuevo o reaccion).
# La pagina lo consulta (1 lectura) y solo pide la lista completa (hasta 20 lecturas)
# cuando la version es distinta de la que ya tiene.
ESTADO = db.collection("meta").document("estado")


def subir_version():
    ESTADO.set({"version": firestore.Increment(1)}, merge=True)


@app.after_request
def permitir_navegador(respuesta):
    respuesta.headers["Access-Control-Allow-Origin"] = os.environ.get("ORIGEN_PERMITIDO", "*")
    respuesta.headers["Access-Control-Allow-Headers"] = "Content-Type"
    respuesta.headers["Access-Control-Allow-Methods"] = "GET, POST"
    respuesta.headers["Vary"] = "Origin"
    return respuesta


@app.get("/")
def salud():
    return "ok"


@app.get("/version")
def version():
    doc = ESTADO.get()
    return jsonify(instancia=INSTANCIA, version=(doc.get("version") if doc.exists else 0))


@app.get("/mensajes")
def listar():
    consulta = (db.collection("mensajes")
                  .order_by("creado", direction=firestore.Query.DESCENDING)
                  .limit(20))
    mensajes = [{
        "id": d.id,
        "autor": d.get("autor"),
        "texto": d.get("texto"),
        "likes": (d.to_dict().get("likes") or 0),
    } for d in consulta.stream()]
    return jsonify(instancia=INSTANCIA, mensajes=mensajes)


@app.post("/mensajes")
def crear():
    datos = request.get_json(silent=True) or {}
    autor = str(datos.get("autor", "")).strip()[:40]
    texto = str(datos.get("texto", "")).strip()[:280]
    if not autor or not texto:
        return jsonify(error="faltan autor o texto"), 400
    db.collection("mensajes").add({
        "autor": autor,
        "texto": texto,
        "likes": 0,
        "creado": firestore.SERVER_TIMESTAMP,
    })
    subir_version()
    return jsonify(ok=True, instancia=INSTANCIA), 201


@app.post("/mensajes/<id_mensaje>/like")
def reaccionar(id_mensaje):
    ref = db.collection("mensajes").document(id_mensaje)
    try:
        # Increment es atomico: dos personas reaccionando a la vez no se pisan.
        ref.update({"likes": firestore.Increment(1)})
    except Exception:
        return jsonify(error="mensaje no encontrado"), 404
    subir_version()
    return jsonify(ok=True, instancia=INSTANCIA), 200
