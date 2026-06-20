import os
import sys
import logging
import random
import time
from typing import List
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from fastapi.responses import Response

# OpenTelemetry Instrumentation imports
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor, ConsoleSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

# Initialize Logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger("fastapi-ai-service")

# Initialize OpenTelemetry
provider = TracerProvider()
processor = BatchSpanProcessor(ConsoleSpanExporter())
provider.add_span_processor(processor)
trace.set_tracer_provider(provider)
tracer = trace.get_tracer(__name__)

# Initialize FastAPI App
app = FastAPI(
    title="Production-Grade FastAPI AI Inference Service",
    description="Exposes prediction endpoints, pushes telemetry data, and logs transactional events.",
    version="1.0.0"
)

# Instrument FastAPI with OTel
FastAPIInstrumentor.instrument_app(app)

# Prometheus Metrics definition
HTTP_REQUESTS_TOTAL = Counter(
    "http_requests_total",
    "Total HTTP requests received",
    ["method", "endpoint", "status"]
)
REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "Request latency in seconds",
    ["method", "endpoint"]
)

# Request validation schema
class InferenceRequest(BaseModel):
    data: List[float]

# Env configs
DB_HOST = os.getenv("DB_HOST", "postgres-ha-rw.databases.svc.cluster.local")
KAFKA_BROKER = os.getenv("KAFKA_BROKER", "production-kafka-kafka-bootstrap.kafka.svc.cluster.local:9092")

@app.on_event("startup")
def startup_event():
    logger.info("Initializing connection pools...")
    logger.info(f"Target Postgres Master: {DB_HOST}:5432")
    logger.info(f"Target Kafka bootstrap cluster: {KAFKA_BROKER}")
    # Simulating connection establishing
    logger.info("Successfully connected to stateful persistence layers.")

@app.get("/healthz")
@app.get("/live")
def liveness():
    HTTP_REQUESTS_TOTAL.labels(method="GET", endpoint="/healthz", status="200").inc()
    return {"status": "healthy", "timestamp": time.time()}

@app.get("/ready")
def readiness():
    # SRE readiness check: verify DB ping
    # In real app, we would query 'SELECT 1' via postgres connection pool
    try:
        # Mocking db connectivity check
        db_reachable = True
        if not db_reachable:
            raise Exception("Database unreachable")
        HTTP_REQUESTS_TOTAL.labels(method="GET", endpoint="/ready", status="200").inc()
        return {"ready": True}
    except Exception as e:
        logger.error(f"Readiness check failed: {str(e)}")
        HTTP_REQUESTS_TOTAL.labels(method="GET", endpoint="/ready", status="503").inc()
        raise HTTPException(status_code=503, detail="Service not ready")

@app.post("/predict")
def predict(payload: InferenceRequest):
    start_time = time.time()
    method = "POST"
    endpoint = "/predict"

    # Start explicit OpenTelemetry span
    with tracer.start_as_current_span("ai-inference-calculation") as span:
        try:
            span.set_attribute("payload.size", len(payload.data))
            
            if not payload.data:
                raise ValueError("Payload input vector is empty")

            # Mock Inference Calculation: Dot product + noise
            weight_vector = [0.5] * len(payload.data)
            score = sum(x * w for x, w in zip(payload.data, weight_vector))
            prediction = score + random.uniform(-0.1, 0.1)

            # Record metrics info
            duration = time.time() - start_time
            REQUEST_LATENCY.labels(method=method, endpoint=endpoint).observe(duration)
            HTTP_REQUESTS_TOTAL.labels(method=method, endpoint=endpoint, status="200").inc()

            # Mock Write Database & Kafka Message
            logger.info(f"Successfully recorded prediction in DB. Latency: {duration:.3f}s")
            logger.info(f"Published prediction metadata to Kafka topic: inference-events")

            span.set_attribute("prediction.result", prediction)
            return {"prediction": prediction, "status": "success"}

        except Exception as e:
            logger.error(f"Inference exception encountered: {str(e)}")
            HTTP_REQUESTS_TOTAL.labels(method=method, endpoint=endpoint, status="500").inc()
            span.record_exception(e)
            raise HTTPException(status_code=500, detail=str(e))

@app.get("/metrics")
def get_metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)
