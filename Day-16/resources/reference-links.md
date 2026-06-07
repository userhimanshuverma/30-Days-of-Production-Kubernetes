# Day 16 Logging Reference Links

Below is a curated collection of official documentation, specifications, and tools to help you design logging systems at an enterprise scale.

---

## Container runtime & Kubernetes native logging
* [Kubernetes Logging Architecture](https://kubernetes.io/docs/concepts/cluster-administration/logging/) — Standard output streams and architecture types.
* [CRI Logging Format Specification](https://github.com/kubernetes/design-proposals-archive/blob/main/node/kubelet-cri-logging.md) — Under the hood details of runtime log outputs.

---

## Log shippers
* [Fluent Bit Documentation](https://docs.fluentbit.io/) — Official parser, filter, and output setup guides.
* [Fluent Bit Inputs: Tail Plugin](https://docs.fluentbit.io/manual/pipeline/inputs/tail) — File tracking configuration details.
* [Fluent Bit Filters: Kubernetes Metadata](https://docs.fluentbit.io/manual/pipeline/filters/kubernetes) — Appending labels dynamically.

---

## Loki & Grafana
* [Grafana Loki Architecture](https://grafana.com/docs/loki/latest/get-started/architecture/) — Distributor, Ingester, and Chunk store internals.
* [LogQL Query Reference Guide](https://grafana.com/docs/loki/latest/query/) — Writing metric query selectors and JSON pipelines.

---

## Elasticsearch & Kibana (EFK)
* [Elasticsearch Reference Documentation](https://www.elastic.co/guide/en/elasticsearch/reference/current/index.html) — Inverted index details, sharding, and mappings.
* [Elasticsearch Index Lifecycle Management (ILM)](https://www.elastic.co/guide/en/elasticsearch/reference/current/index-lifecycle-management.html) — Automating rollovers and disk watermark cleanups.
