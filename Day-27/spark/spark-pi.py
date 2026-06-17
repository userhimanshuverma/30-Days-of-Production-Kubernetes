#!/usr/bin/env python3
"""
spark-pi.py
-----------
A production-grade sample Spark application designed to run on Kubernetes.
Calculates Pi using Monte Carlo simulation.
"""

import sys
from random import random
from operator import add
from pyspark.sql import SparkSession

def main():
    # Initialize the SparkSession. When running on Kubernetes, the master URL
    # is typically set to "k8s://https://kubernetes.default.svc" via spark-submit,
    # or inferred automatically when running inside a driver pod.
    spark = SparkSession.builder \
        .appName("KubernetesSparkPi") \
        .getOrCreate()

    partitions = int(sys.argv[1]) if len(sys.argv) > 1 else 100
    n = 100000 * partitions

    def f(_):
        x = random() * 2 - 1
        y = random() * 2 - 1
        return 1 if x ** 2 + y ** 2 <= 1 else 0

    print(f"Starting Spark Pi computation with {partitions} partitions...")
    print(f"Total samples to execute: {n}")

    # Parallelize the workload. The driver divides the task into partitions
    # and distributes them across the dynamic Executor Pods.
    count = spark.sparkContext.parallelize(range(1, n + 1), partitions) \
        .map(f) \
        .reduce(add)

    pi_val = 4.0 * count / n
    print("-------------------------------------------------------------------")
    print(f"Pi is roughly {pi_val}")
    print("-------------------------------------------------------------------")

    spark.stop()

if __name__ == "__main__":
    main()
