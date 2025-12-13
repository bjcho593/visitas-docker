from fastapi import FastAPI
import redis
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()

# Configurar CORS para permitir que el frontend hable con este backend
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Conexión a Redis. 
# OJO: 'redis-db' es el nombre que le pondremos al servicio en el docker-compose.
r = redis.Redis(host='redis-db', port=6379, decode_responses=True)

@app.get("/")
def read_root():
    return {"Estado": "API Activa"}

@app.get("/visitas")
def contar_visitas():
    # Incrementa el contador en Redis automáticamente
    count = r.incr('contador_visitas')
    return {"visitas": count}