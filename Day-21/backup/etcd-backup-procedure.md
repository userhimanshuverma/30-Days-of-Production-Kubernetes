# 💾 etcd Backup Procedure (Production Runbook)

This guide documents the procedures for backing up **etcd**, the distributed key-value store that maintains the entire state of your Kubernetes cluster. If etcd is lost and you have no backup, your cluster cannot be recovered.

---

## 🛡️ Pre-Requisites
Before attempting a backup, ensure you have:
1. **Root/sudo access** on a control plane node.
2. The `etcdctl` CLI installed.
3. Access to etcd's TLS certificate authority (`ca.crt`), client certificate (`server.crt`), and private key (`server.key`).
   - Default path in `kubeadm` clusters: `/etc/kubernetes/pki/etcd/`

---

## 🏃 Procedure 1: Manual Backup via CLI

1. **SSH to the primary control-plane node**:
   ```bash
   ssh admin@control-plane-01.c.prod-cluster.internal
   ```

2. **Locate certificates and IP endpoints**:
   You can extract this from the static pod manifest at `/etc/kubernetes/manifests/etcd.yaml`:
   ```bash
   grep -E "(listen-client-urls|cert-file|key-file|trusted-ca-file)" /etc/kubernetes/manifests/etcd.yaml
   ```

3. **Take the snapshot**:
   Run the following command as `root`:
   ```bash
   sudo ETCDCTL_API=3 etcdctl \
     --endpoints=https://127.0.0.1:2379 \
     --cacert=/etc/kubernetes/pki/etcd/ca.crt \
     --cert=/etc/kubernetes/pki/etcd/server.crt \
     --key=/etc/kubernetes/pki/etcd/server.key \
     snapshot save /var/backups/kubernetes/etcd/snapshot-manual-$(date +%s).db
   ```

---

## 🔍 Procedure 2: Verification of Backup Integrity

A snapshot file might be created successfully but still be corrupt. You **must** verify it:

1. **Run the status check**:
   ```bash
   sudo ETCDCTL_API=3 etcdctl --write-out=table snapshot status /var/backups/kubernetes/etcd/snapshot-manual-<timestamp>.db
   ```

2. **Expected Output**:
   ```text
   +----------+----------+------------+------------+
   |   HASH   | REVISION | TOTAL KEYS | TOTAL SIZE |
   +----------+----------+------------+------------+
   | c8df21b0 |  4820194 |       8102 |     4.2 MB |
   +----------+----------+------------+------------+
   ```
   *If the hash or revision fields are empty, or the CLI returns an error, the file is corrupt and cannot be used for recovery.*

---

## ⏰ Procedure 3: Scheduled Automation via Systemd Cron

While Kubernetes CronJobs are excellent, running etcd backups as a local **Systemd service/timer** on the control plane nodes provides a fallback if the Kubernetes API itself is degraded.

### 1. Create a systemd service file
Create `/etc/systemd/system/etcd-backup.service`:
```ini
[Unit]
Description=Kubernetes etcd backup service
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/etcd-backup.sh
User=root
Group=root
```

### 2. Create a systemd timer file
Create `/etc/systemd/system/etcd-backup.timer`:
```ini
[Unit]
Description=Run etcd-backup service hourly

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
```

### 3. Enable and start the timer
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now etcd-backup.timer
```

---

## 📦 Offsite Backup Replication (RPO Strategy)

To achieve a strong RPO, local snapshots must be copied to a separate storage class or regional cloud bucket.

### AWS S3 Example
Add the following command to your backup script:
```bash
aws s3 cp /var/backups/kubernetes/etcd/etcd-snapshot-${TIMESTAMP}.db s3://company-k8s-dr-backups/etcd-snapshots/$(hostname)/
```

### GCS Example
```bash
gcloud storage cp /var/backups/kubernetes/etcd/etcd-snapshot-${TIMESTAMP}.db gs://company-k8s-dr-backups/etcd-snapshots/$(hostname)/
```

### Azure Blob Example
```bash
az storage blob upload \
  --account-name k8sdrstorage \
  --container-name etcd-backups \
  --file /var/backups/kubernetes/etcd/etcd-snapshot-${TIMESTAMP}.db \
  --name $(hostname)/etcd-snapshot-${TIMESTAMP}.db
```
