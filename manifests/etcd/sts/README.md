# etcd StatefulSet 部署

本目录提供两套三节点 etcd StatefulSet：

- `etcd.yaml`：启用客户端 TLS、peer TLS 和双向证书校验。
- `etcd-insecure.yaml`：不启用 TLS，2379/2380 使用 HTTP。
- `certificates.yaml`：TLS 版本使用的 cert-manager 证书资源。

两套 StatefulSet 使用相同的资源名 `etcd`，只能选择其中一套部署，不能同时应用。

每套清单都包含两个 Service：

- `etcd`：Headless Service，仅用于 StatefulSet 的稳定 Pod DNS 和 peer 通信。
- `etcd-client`：普通 ClusterIP Service，暴露 2379 供应用访问，并暴露 8080 供监控采集。

应用访问地址：

```text
TLS：    https://etcd-client:2379
非 TLS： http://etcd-client:2379
```

TLS 客户端仍需使用 `etcd-client-tls` 中的客户端证书、私钥和 CA。

监控系统可通过以下地址采集 etcd 指标：

```text
http://etcd-client:8080/metrics
```

Service 的监控端口名称为 `etcd-metrics`，可直接被 ServiceMonitor 或其他基于 Service 端口发现的采集器使用。

## TLS 版本

先安装 cert-manager：

```bash
helm repo add jetstack https://charts.jetstack.io
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true
```

再按顺序创建证书、等待证书就绪、部署 StatefulSet：

```bash
kubectl -n default apply -f manifests/etcd/sts/certificates.yaml

kubectl -n default wait \
  --for=condition=Ready \
  certificate/etcd-ca \
  certificate/etcd-server \
  certificate/etcd-client \
  --timeout=180s

kubectl -n default apply -f manifests/etcd/sts/etcd.yaml
kubectl -n default rollout status statefulset/etcd
```

验证集群健康状态：

```bash
kubectl -n default exec etcd-0 -- \
  etcdctl endpoint health --cluster
```

TLS 版本的证书和 StatefulSet 固定在 `default` 命名空间，证书 SAN 也包含 `default` 的完整 Service DNS。迁移到其他命名空间时，需要同步修改 TLS 清单中的命名空间和 SAN。

## 非 TLS 版本

非 TLS 版本不需要 cert-manager，也不要应用 `certificates.yaml`：

```bash
kubectl apply -f manifests/etcd/sts/etcd-insecure.yaml
kubectl rollout status statefulset/etcd
```

验证集群健康状态：

```bash
kubectl exec -n <目标命名空间> etcd-0 -- \
  etcdctl endpoint health --cluster

kubectl exec -n api-games etcd-0 -- \
  etcdctl endpoint health --cluster

```

## 注意事项

- 两套清单都是新建三节点集群配置，`--initial-cluster-state=new` 只适合首次初始化。
- 已有集群不能直接在 HTTP 和 HTTPS 清单之间切换后滚动重启；切换前需要备份并规划成员 peer URL 迁移。
- 当前 PVC 使用 `alicloud-disk-essd`，集群没有该 StorageClass 时需要改成实际可用的 StorageClass。

## 查看 Leader 和常用命令

以下命令在 Pod 内执行。TLS 版本会自动读取 Pod 中的 `ETCDCTL_*` 证书环境变量，非 TLS 版本会读取 `ETCDCTL_ENDPOINTS`。

查看所有成员状态，表格中 `IS LEADER=true` 的 endpoint 就是当前 Leader：

```bash
kubectl exec -n <目标命名空间> etcd-0 -- \
  etcdctl endpoint status --cluster -w table
```

只输出 Leader endpoint：

```bash
kubectl exec -n <目标命名空间> etcd-0 -- \
  sh -c 'etcdctl endpoint status --cluster -w json' \
  | jq -r '.[] | select(.Status.leader == .Status.header.member_id) | .Endpoint'
```

常用只读检查：

```bash
# 检查所有 endpoint 是否健康
kubectl exec -n <目标命名空间> etcd-0 -- \
  etcdctl endpoint health --cluster

# 查看成员列表
kubectl exec -n <目标命名空间> etcd-0 -- \
  etcdctl member list -w table

# 查看 endpoint 延迟、版本、Leader 和数据库大小
kubectl exec -n <目标命名空间> etcd-0 -- \
  etcdctl endpoint status --cluster -w table

# 查看告警
kubectl exec -n <目标命名空间> etcd-0 -- \
  etcdctl alarm list
```

常用维护命令：

```bash
# 查看 KV
kubectl exec -n <目标命名空间> etcd-0 -- \
  etcdctl get / --prefix --keys-only

# 查看某个 key 的值
kubectl exec -n <目标命名空间> etcd-0 -- \
  etcdctl get /path/to/key

# 查看当前 revision
kubectl exec -n <目标命名空间> etcd-0 -- \
  etcdctl endpoint status --cluster -w json | jq '.[].Status.header'

# 查看空间使用情况
kubectl exec -n <目标命名空间> etcd-0 -- \
  etcdctl endpoint status --cluster -w table
```

以下命令会修改集群或数据，执行前先确认目标成员和备份：

```bash
# 保存快照
kubectl exec -n <目标命名空间> etcd-0 -- \
  etcdctl snapshot save /tmp/etcd-snapshot.db

# 压缩历史 revision（revision 替换为实际值）
kubectl exec -n <目标命名空间> etcd-0 -- \
  etcdctl compact <revision>

# 回收每个成员的磁盘空间；需要逐个成员执行
kubectl exec -n <目标命名空间> etcd-0 -- \
  etcdctl defrag
```

`member add`、`member remove`、`member update`、`snapshot restore`、`alarm disarm` 会改变集群或数据，除非明确知道目标和参数，不要直接执行。
