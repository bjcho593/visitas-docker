FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Uvicorn es el servidor que corre FastAPI
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]