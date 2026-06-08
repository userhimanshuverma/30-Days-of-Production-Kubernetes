# 📚 Day 17 Reference Links & Recommended Reading

Below are curated links and resources to extend your knowledge of Prometheus, Grafana, alerting systems, and enterprise observability scaling.

---

## Official Documentation
*   [Prometheus Documentation](https://prometheus.io/docs/introduction/overview/) — Official guide covering TSDB architecture, scrape configs, and querying.
*   [Grafana Documentation](https://grafana.com/docs/) — Documentation on panels, provisioners, variables, and alerts.
*   [Alertmanager Documentation](https://prometheus.io/docs/alerting/latest/alertmanager/) — Reference for silences, inhibitions, grouping, and notification routing.

## PromQL & Query Guides
*   [Prometheus Querying Basics](https://prometheus.io/docs/prometheus/latest/querying/basics/) — Official PromQL operator and syntax reference.
*   [Prom Labs PromQL Cheat Sheet](https://promlabs.com/promql-cheat-sheet/) — A visual, printable handbook of common PromQL functions and vectors.

## Exporters & Dashboards
*   [Prometheus Exporters List](https://prometheus.io/docs/instrumenting/exporters/) — Database, hardware, search, messaging, and system collectors catalog.
*   [Grafana Dashboard Public Repository](https://grafana.com/grafana/dashboards/) — Community-contributed dashboards (e.g. search for dashboard ID `1860` for Node Exporter, or `8685` for Kube-State-Metrics).
*   [kube-state-metrics Repository](https://github.com/kubernetes/kube-state-metrics) — Official source code and metric exposure documentation.

## Alerting Libraries
*   [Awesome Prometheus Alerts](https://awesome-prometheus-alerts.grep.to/) — A comprehensive library of 400+ collection-ready Alerting Rules grouped by service (Kubernetes, databases, networks, runtimes).

## Observability at Scale
*   [Thanos Project Home](https://thanos.io/) — Global PromQL querying, remote-write receiver, and long-term storage design.
*   [Grafana Mimir Project Home](https://grafana.com/oss/mimir/) — High-performance multi-tenant time-series metrics engine.
*   [VictoriaMetrics Project Home](https://victoriametrics.com/) — Alternative fast, cost-efficient, long-term storage database.
*   [Google SRE Book - Monitoring Distributed Systems](https://sre.google/sre-book/monitoring-distributed-systems/) — SRE design principles from Google.
*   [Google SRE Book - Practical Alerting (SLOs)](https://sre.google/workbook/alerting-on-slos/) — Advanced math behind multi-window multi-burn-rate alerting.
