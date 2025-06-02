# Istio 流量管理 - 服务子集示例

本示例演示了如何使用 Istio 的流量管理功能实现服务版本控制和流量分配。通过 DestinationRule 和 VirtualService 资源，将流量按比例路由到不同版本的后端服务。

## 应用架构

本示例部署了同一应用的两个不同版本：

- **Demoapp v2.0**
  - 镜像: `vvoo/demoapp:v2.0`
  - 部署: 2 个副本
  - 标签: `version: v2.0`
  - 环境变量:
    - `PORT`: 8080
    - `VERSION`: v2.0

- **Demoapp v2.1**
  - 镜像: `vvoo/demoapp:v2.1`
  - 部署: 2 个副本
  - 标签: `version: v2.1`
  - 环境变量:
    - `PORT`: 8080
    - `VERSION`: v2.1

两个版本共用同一个 Service：`demoapp`，通过 Istio 的流量管理功能进行请求分发。

## Istio 流量管理配置

### DestinationRule

定义了两个服务子集:
- `v20`: 对应 `version: v2.0` 标签的 Pod
- `v21`: 对应 `version: v2.1` 标签的 Pod

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: demoapp
spec:
  host: demoapp
  subsets:
  - name: v20
    labels:
      version: v2.0
  - name: v21
    labels: 
      version: v2.1
```

### VirtualService

配置流量分配规则:
- 80% 的流量路由到 `v20` 子集
- 20% 的流量路由到 `v21` 子集

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: demoapp
spec:
  hosts:
    - demoapp
  http:
  - route:
    - destination: 
        host: demoapp
        subset: v20
      weight: 80
    - destination:
        host: demoapp
        subset: v21
      weight: 20
```

## 部署说明

按以下顺序部署应用和 Istio 配置:

```bash
# 部署两个版本的应用
kubectl apply -f deploy-demoapp.yaml
kubectl apply -f deploy-demoapp-v21.yaml

# 应用 Istio 流量管理配置
kubectl apply -f destinationrule.yaml
kubectl apply -f virtualservice.yaml
```

## 访问测试

使用以下命令测试流量分配:

```bash
kubectl run client -it --rm --image=vvoo/admin-box --restart=Never --command -- bash
while true; do curl demoapp ; sleep 0.$RANDOM; done
```

观察输出，应该能看到大约 80% 的请求返回 v2.0 版本的响应，20% 的请求返回 v2.1 版本的响应。
