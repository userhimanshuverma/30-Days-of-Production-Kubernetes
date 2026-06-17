# Resources & Recommended Reading: Data Platforms on Kubernetes

This curated reference list covers the critical resources, books, official operators, and production engineering blogs for learning how to deploy and operate data systems on Kubernetes.

---

## 1. Official Operators & Frameworks

* **Apache Spark on Kubernetes**:
  * [Spark on K8s official documentation](https://spark.apache.org/docs/latest/running-on-kubernetes.html)
  * [GoogleCloudPlatform Spark-on-k8s Operator](https://github.com/GoogleCloudPlatform/spark-on-k8s-operator) - The community standard CRD operator for Spark.
* **Apache Airflow**:
  * [Airflow Official Helm Chart](https://airflow.apache.org/docs/helm-chart/stable/index.html)
  * [Airflow KubernetesExecutor architecture details](https://airflow.apache.org/docs/apache-airflow/stable/executor/kubernetes.html)
* **Apache Kafka**:
  * [Strimzi Kafka Operator](https://strimzi.io/) - CNCF project providing custom resources for Kafka clusters, topics, and users.
  * [Confluent Operator for Kubernetes](https://www.confluent.io/operator/) - Enterprise operator.
* **Apache Pinot**:
  * [Apache Pinot Helm Charts](https://docs.pinot.apache.org/getting-started/kubernetes-setup)
  * [Pinot real-time ingestion from Kafka configs](https://docs.pinot.apache.org/concepts/pinot-architecture)

---

## 2. Engineering Blogs & Case Studies

* **Netflix Technology Blog**:
  * [How Netflix runs Spark on Kubernetes](https://netflixtechblog.com/) - Key lessons on multi-tenancy, dynamic allocation, and storage mount patterns.
* **Uber Engineering Blog**:
  * [Stateful workloads on Kubernetes](https://www.uber.com/blog/) - Read about how Uber migrated their Kafka and storage systems to Kubernetes.
* **Linkedin Engineering**:
  * [Scaling real-time Pinot engines](https://engineering.linkedin.com/) - Discusses segment design, query scatter-gather routing overhead, and OS page cache tuning.
* **Databricks Engineering**:
  * [Best practices for large-scale Spark scheduling](https://www.databricks.com/blog/)

---

## 3. Recommended Books

* *"Designing Data-Intensive Applications"* by Martin Kleppmann (O'Reilly). The definitive guide to understanding storage engines, indexes, consensus (ZooKeeper), and streaming replication.
* *"Kubernetes Patterns"* by Bilgin Ibryam and Roland Huß (O'Reilly). Covers the Operator pattern, Custom Resources, and Init containers.
* *"Cloud Native Infrastructure"* by Justin Garrison and Kris Nova.
