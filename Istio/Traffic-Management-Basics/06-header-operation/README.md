# Istio 流量管理 - HTTP 请求头操作示例

本示例演示了 Istio 的 HTTP 请求头操作功能，包括基于请求头的路由、请求头修改和响应头添加等高级流量管理功能。通过这些功能，可以实现更精细的流量控制和用户体验定制。

## 应用架构

本示例部署了同一应用的两个不同版本：

- **Demoapp v2.0** (稳定版本)
  - 镜像: `vvoo/demoapp:v2.0`
  - 部署: 2 个副本
  - 标签: `version: v2.0`
  - 环境变量:
    - `PORT`: 8080
    - `VERSION`: v2.0

- **Demoapp v2.1** (金丝雀版本)
  - 镜像: `vvoo/demoapp:v2.0` (使用相同镜像，通过环境变量区分版本)
  - 部署: 2 个副本
  - 标签: `version: v2.1`
  - 环境变量:
    - `PORT`: 8080
    - `VERSION`: v2.1

两个版本共用同一个 Service：`demoapp`，通过 Istio 的流量管理功能进行请求分发。

## HTTP 请求头操作功能说明

本示例实现了三种不同的 HTTP 请求头操作：

1. **基于请求头的路由**
   - 当请求头中包含 `x-canary: true` 时，请求被路由到金丝雀版本（v2.1）
   - 其他请求则路由到稳定版本（v2.0）

2. **请求头修改**
   - 对于金丝雀版本的请求，将 `User-Agent` 请求头设置为 `Chrome`
   - 这个修改对上游服务可见，但对客户端不可见

3. **响应头添加**
   - 对于金丝雀版本的响应，添加 `x-canary: true` 响应头
   - 对于稳定版本的响应，添加 `X-Envoy: true` 响应头
   - 这些修改对客户端可见，但对上游服务不可见

## Istio 流量管理配置

### DestinationRule

定义了两个服务子集:
- `v20`: 对应 `version: v2.0` 标签的 Pod（稳定版本）
- `v21-canary`: 对应 `version: v2.1` 标签的 Pod（金丝雀版本）

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: demoapp
spec:
  host: demoapp
  subsets:
  - name: v20
    labels:
      version: v2.0
  - name: v21-canary
    labels: 
      version: v2.1
```

### VirtualService

配置基于请求头的路由和 HTTP 请求头操作:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: demoapp
spec:
  hosts:
    - demoapp
  http:
    - name: header-operation-canary # 基于请求头的金丝雀路由
      match:
      - headers:
          x-canary:
            exact: "true" # 匹配请求头中 x-canary=true 的请求
      route:
      - destination:
          host: demoapp
          subset: v21-canary # 路由到金丝雀版本
        headers:
          request:
            set:
              User-Agent: Chrome # 设置请求头
          response:
            add:
              x-canary: "true" # 添加响应头
    - name: default # 默认规则
      headers:
        response:
          add:
            X-Envoy: "true" # 添加响应头
      route:
      - destination:
          host: demoapp
          subset: v20 # 路由到稳定版本
```

## 部署说明

按以下顺序部署应用和 Istio 配置:

```bash
# 部署两个版本的应用
kubectl apply -f deploy-demoapp.yaml
kubectl apply -f deploy-demoapp-v21.yaml

# 应用 Istio 流量管理配置
kubectl apply -f destinationrule.yaml
kubectl apply -f virtualservice-demoapp.yaml
```

## 访问测试

使用以下命令测试不同的请求头:

```bash
# 创建测试客户端
kubectl run client -it --rm --image=vvoo/admin-box --restart=Never --command -- bash

# 测试默认路由（应该路由到 v2.0 版本）
curl -v demoapp/

# 测试带有 x-canary 请求头的请求（应该路由到 v2.1 版本）
curl -v -H "x-canary: true" demoapp/
```

观察响应和响应头，验证路由规则和请求头操作是否生效。

## HTTP 请求头操作的应用场景

1. **用户分组测试**
   - 根据用户 ID、会话 ID 或其他标识符将特定用户路由到新版本
   - 例如：对内部测试人员或特定用户组启用新功能

2. **A/B 测试**
   - 根据用户代理、地理位置或其他属性分流不同用户
   - 例如：为移动用户和桌面用户提供不同的体验

3. **调试和故障排除**
   - 添加特定请求头以追踪请求流程
   - 例如：添加请求 ID 或跟踪标识符

4. **安全增强**
   - 移除或修改可能包含敏感信息的请求头
   - 例如：过滤掉内部服务间通信中不需要的认证信息
