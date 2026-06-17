#!/usr/bin/env python3
"""
consumer.py
-----------
A production-grade Python consumer client designed to read and process events
from Kafka running inside a Kubernetes cluster.
"""

import sys
import json
from kafka import KafkaConsumer
from kafka.errors import KafkaError

# Configuration
BOOTSTRAP_SERVERS = ['production-kafka-kafka-bootstrap.default.svc.cluster.local:9092']
TOPIC_NAME = 'user-clicks'
GROUP_ID = 'production-analytics-consumers'

def main():
    print("Initializing Kafka Consumer...")
    print(f"Connecting to Bootstrap Server: {BOOTSTRAP_SERVERS}")
    print(f"Subscribing to: {TOPIC_NAME} as member of Group ID: {GROUP_ID}")

    # Production-grade parameters:
    # - enable_auto_commit=False: Manually commit offsets after processing records (at-least-once guarantee).
    # - auto_offset_reset='earliest': Consume from oldest logs if group has no committed offsets.
    try:
        consumer = KafkaConsumer(
            TOPIC_NAME,
            bootstrap_servers=BOOTSTRAP_SERVERS,
            group_id=GROUP_ID,
            value_deserializer=lambda m: json.loads(m.decode('utf-8')),
            enable_auto_commit=False,
            auto_offset_reset='earliest',
            session_timeout_ms=10000,
            heartbeat_interval_ms=3000
        )
    except Exception as e:
        print(f"Failed to create consumer: {e}", file=sys.stderr)
        sys.exit(1)

    print("Consumer registration successful! Awaiting partition messages...")
    print("Press Ctrl+C to terminate.")

    try:
        for message in consumer:
            payload = message.value
            print(f"📥 Received — Partition: {message.partition} | Offset: {message.offset} | Key: {message.key}")
            print(f"    Payload: Event={payload['event_id']} | User={payload['user_id']} | Page={payload['page_url']} | Revenue=${payload['revenue_usd']}")
            
            # --- Business Logic/ETL Processing happens here ---
            # If processing takes time, batch commits or async processing should be used.
            
            # Manually commit offset for the processed partition batch
            try:
                consumer.commit()
            except KafkaError as commit_err:
                print(f"⚠️ Offset commit failed: {commit_err}", file=sys.stderr)
                
    except KeyboardInterrupt:
        print("\nConsumer interrupted by user. Exiting...")
    finally:
        consumer.close()
        print("Kafka Consumer shut down safely.")

if __name__ == '__main__':
    main()
