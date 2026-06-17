#!/usr/bin/env python3
"""
producer.py
-----------
A production-grade Python producer client designed to write events to Kafka
running inside a Kubernetes cluster (e.g., Strimzi deployment).
"""

import time
import json
import random
import sys
from kafka import KafkaProducer
from kafka.errors import KafkaError

# Configuration
BOOTSTRAP_SERVERS = ['production-kafka-kafka-bootstrap.default.svc.cluster.local:9092']
TOPIC_NAME = 'user-clicks'

def generate_telemetry_event():
    pages = ['/home', '/products', '/cart', '/checkout', '/dashboard', '/pricing']
    platforms = ['iOS', 'Android', 'Web', 'Desktop']
    
    return {
        'timestamp': int(time.time() * 1000),
        'event_id': f"evt_{random.randint(10000000, 99999999)}",
        'user_id': f"usr_{random.randint(1000, 9999)}",
        'page_url': random.choice(pages),
        'duration_ms': random.randint(50, 15000),
        'platform': random.choice(platforms),
        'revenue_usd': round(random.uniform(0.0, 99.99), 2) if random.random() > 0.8 else 0.0
    }

def on_send_success(record_metadata):
    print(f"✅ Event sent. Topic: {record_metadata.topic} | Partition: {record_metadata.partition} | Offset: {record_metadata.offset}")

def on_send_error(excp):
    print(f"❌ Error while producing message: {excp}", file=sys.stderr)

def main():
    print("Initializing Kafka Producer...")
    print(f"Connecting to Bootstrap Server: {BOOTSTRAP_SERVERS}")

    # Production-grade parameters:
    # - acks='all': Ensures partition replicas write before sending acknowledgment (zero data loss).
    # - retries: Re-sends transient network failure messages.
    # - compression_type='gzip': Compresses batches to minimize network traffic and storage footprints.
    try:
        producer = KafkaProducer(
            bootstrap_servers=BOOTSTRAP_SERVERS,
            value_serializer=lambda v: json.dumps(v).encode('utf-8'),
            acks='all',
            retries=5,
            compression_type='gzip',
            max_in_flight_requests_per_connection=1,
            request_timeout_ms=30000
        )
    except Exception as e:
        print(f"Failed to create producer: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"Producer connected! Starting stream to topic: {TOPIC_NAME}")
    print("Press Ctrl+C to terminate.")

    try:
        while True:
            event = generate_telemetry_event()
            # Send message asynchronously, supplying validation callbacks
            producer.send(TOPIC_NAME, value=event).add_callback(on_send_success).add_errback(on_send_error)
            
            # Throttle stream: send 1-5 messages per second
            time.sleep(random.uniform(0.2, 1.0))
    except KeyboardInterrupt:
        print("\nProducer interrupted by user. Flushing buffered records...")
    finally:
        # Block until all pending messages are sent
        producer.close(timeout=10)
        print("Kafka Producer shut down safely.")

if __name__ == '__main__':
    main()
