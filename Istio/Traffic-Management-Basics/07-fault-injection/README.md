# Istio 流量管理 - 故障注入示例

本示例演示了 Istio 的故障注入（Fault Injection）功能，通过在服务网格层面注入延迟和错误，模拟各种故障场景，用于测试应用程序的弹性和容错能力。

官网文档: https://istio.io/latest/zh/docs/tasks/traffic-management/fault-injection/

## 应用架构

本示例部署了同一应用的两个不同版本：

- **Demoapp v2.0** (稳定版本)
  - 镜像: `vvoo/demoapp:v2.0`
  - 部署: 2 个副本
  - 标签: `version: v2.0`
  - 环境变量:
    - `PORT`: 8080
    - `VERSION`: v2.0
  - 故障注入: 50% 的请求会有 3 秒延迟

- **Demoapp v2.1** (金丝雀版本)
  - 镜像: `vvoo/demoapp:v2.0` (使用相同镜像，通过环境变量区分版本)
  - 部署: 2 个副本
  - 标签: `version: v2.1`
  - 环境变量:
    - `PORT`: 8080
    - `VERSION`: v2.1
  - 故障注入: 20% 的请求会返回 HTTP 500 错误

本示例还包含一个前端应用，用于展示故障注入的效果：

- **Frontend**
  - 镜像: `vvoo/frontend:v1.1`
  - 部署: 1 个副本
  - 环境变量:
    - `BACKEND_URL`: http://demoapp:80
    - `PORT`: 5901
    - `PROXY_VERSION`: v1.1

## 故障注入功能说明

Istio 提供了两种类型的故障注入：

1. **延迟注入 (Delay)**
   - 在请求处理过程中引入人为延迟
   - 模拟网络延迟、服务过载等场景
   - 用于测试应用程序的超时处理和降级策略

2. **错误注入 (Abort)**
   - 直接返回指定的 HTTP 错误码
   - 模拟服务崩溃、不可用等场景
   - 用于测试应用程序的错误处理和故障恢复能力

故障注入可以根据请求的特定属性（如路径、请求头等）有选择地应用，并且可以设置故障发生的概率。

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

配置基于请求头的路由和故障注入:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: demoapp
spec:
  hosts:
    - demoapp
  http:
    - name: canary # 金丝雀版本路由规则
      match:
      - headers:
          x-canary:
            exact: "true" # 匹配请求头中 x-canary=true 的请求
      route:
      - destination:
          host: demoapp
          subset: v21-canary # 路由到金丝雀版本
      fault: # HTTP 中断故障注入
        abort:
          httpStatus: 500 # 注入 HTTP 500 错误
          percentage:
            value: 20 # 20% 的请求会被注入故障
    - name: default # 默认规则
      fault: # 延迟故障注入
        delay:
          fixedDelay: 3s # 注入 3 秒的固定延迟
          percentage:
            value: 50 # 50% 的请求会被注入延迟
      route:
      - destination:
          host: demoapp
          subset: v20 # 路由到稳定版本
```

## 部署说明

按以下顺序部署应用和 Istio 配置:

```bash
# 部署应用
kubectl apply -f deploy-demoapp.yaml
kubectl apply -f deploy-demoapp-v21.yaml
kubectl apply -f deploy-frontend.yaml

# 应用 Istio 流量管理配置
kubectl apply -f destinationrule.yaml
kubectl apply -f virtualservice-demoapp.yaml
```

## 访问测试

### 延迟测试

使用以下命令测试延迟注入:

```bash
# 创建测试客户端
kubectl run client -it --rm --image=vvoo/admin-box --restart=Never --command -- bash

# 多次请求默认路由，观察延迟情况
while true; do curl frontend; sleep 0.$RANDOM; done
```

#### 延迟测试结果

```
Frontend Proxy v1.1 | Request Time: 3000ms | Backend: demoapp-6b9b7b4b4b-lz5s9
Demoapp by vvoo! App Version: v2.0, Client IP: 127.0.0.6, Server Name: demoapp-6b9b7b4b4b-lz5s9, Server IP: 10.244.2.33 ~
Frontend Proxy v1.1 | Request Time: 6ms | Backend: demoapp-6b9b7b4b4b-lz5s9
Demoapp by vvoo! App Version: v2.0, Client IP: 127.0.0.6, Server Name: demoapp-6b9b7b4b4b-lz5s9, Server IP: 10.244.2.33 ~
Frontend Proxy v1.1 | Request Time: 4ms | Backend: demoapp-6b9b7b4b4b-lz5s9
Demoapp by vvoo! App Version: v2.0, Client IP: 127.0.0.6, Server Name: demoapp-6b9b7b4b4b-lz5s9, Server IP: 10.244.2.33 ~
Frontend Proxy v1.1 | Request Time: 3ms | Backend: demoapp-6b9b7b4b4b-lz5s9
Demoapp by vvoo! App Version: v2.0, Client IP: 127.0.0.6, Server Name: demoapp-6b9b7b4b4b-lz5s9, Server IP: 10.244.2.33 ~
Frontend Proxy v1.1 | Request Time: 3011ms | Backend: demoapp-6b9b7b4b4b-lz5s9
Demoapp by vvoo! App Version: v2.0, Client IP: 127.0.0.6, Server Name: demoapp-6b9b7b4b4b-lz5s9, Server IP: 10.244.2.33 ~
Frontend Proxy v1.1 | Request Time: 2997ms | Backend: demoapp-6b9b7b4b4b-lz5s9
Demoapp by vvoo! App Version: v2.0, Client IP: 127.0.0.6, Server Name: demoapp-6b9b7b4b4b-lz5s9, Server IP: 10.244.2.33 ~
Frontend Proxy v1.1 | Request Time: 4ms | Backend: demoapp-6b9b7b4b4b-lz5s9
Demoapp by vvoo! App Version: v2.0, Client IP: 127.0.0.6, Server Name: demoapp-6b9b7b4b4b-lz5s9, Server IP: 10.244.2.33 ~
Frontend Proxy v1.1 | Request Time: 5ms | Backend: demoapp-6b9b7b4b4b-2qt7c
Demoapp by vvoo! App Version: v2.0, Client IP: 127.0.0.6, Server Name: demoapp-6b9b7b4b4b-2qt7c, Server IP: 10.244.1.49 ~
Frontend Proxy v1.1 | Request Time: 4ms | Backend: demoapp-6b9b7b4b4b-2qt7c
Demoapp by vvoo! App Version: v2.0, Client IP: 127.0.0.6, Server Name: demoapp-6b9b7b4b4b-2qt7c, Server IP: 10.244.1.49 ~
Frontend Proxy v1.1 | Request Time: 3004ms | Backend: demoapp-6b9b7b4b4b-lz5s9
Demoapp by vvoo! App Version: v2.0, Client IP: 127.0.0.6, Server Name: demoapp-6b9b7b4b4b-lz5s9, Server IP: 10.244.2.33 ~
Frontend Proxy v1.1 | Request Time: 2999ms | Backend: demoapp-6b9b7b4b4b-2qt7c
Demoapp by vvoo! App Version: v2.0, Client IP: 127.0.0.6, Server Name: demoapp-6b9b7b4b4b-2qt7c, Server IP: 10.244.1.49 ~
Frontend Proxy v1.1 | Request Time: 8ms | Backend: demoapp-6b9b7b4b4b-2qt7c
Demoapp by vvoo! App Version: v2.0, Client IP: 127.0.0.6, Server Name: demoapp-6b9b7b4b4b-2qt7c, Server IP: 10.244.1.49 ~
```

从结果可以看出，约 50% 的请求响应时间在 3000ms 左右（注入了 3 秒延迟），其余请求响应时间正常（几毫秒）。

### 错误注入测试

使用以下命令测试错误注入:

```bash
# 创建测试客户端
kubectl run client -it --rm --image=vvoo/admin-box --restart=Never --command -- bash

# 多次请求金丝雀版本，观察错误情况
while true; do curl -s -H "x-canary: true" frontend ; sleep 0.$RANDOM; done
```

#### 错误注入测试结果

```
Frontend Proxy v1.1 | Request Time: 5ms | Backend: demoappv21-64498597c-r2lt9
Demoapp by vvoo! App Version: v2.1, Client IP: 127.0.0.6, Server Name: demoappv21-64498597c-r2lt9, Server IP: 10.244.2.39 ~
Frontend Proxy v1.1 | Request Time: 3ms | Backend: demoappv21-64498597c-r2lt9
Demoapp by vvoo! App Version: v2.1, Client IP: 127.0.0.6, Server Name: demoappv21-64498597c-r2lt9, Server IP: 10.244.2.39 ~
Frontend Proxy v1.1 | Request Time: 3ms | Backend: unknown
fault filter abortFrontend Proxy v1.1 | Request Time: 2ms | Backend: unknown
fault filter abortFrontend Proxy v1.1 | Request Time: 4ms | Backend: demoappv21-64498597c-r2lt9
Demoapp by vvoo! App Version: v2.1, Client IP: 127.0.0.6, Server Name: demoappv21-64498597c-r2lt9, Server IP: 10.244.2.39 ~
Frontend Proxy v1.1 | Request Time: 6ms | Backend: demoappv21-64498597c-29z6r
Demoapp by vvoo! App Version: v2.1, Client IP: 127.0.0.6, Server Name: demoappv21-64498597c-29z6r, Server IP: 10.244.1.51 ~
Frontend Proxy v1.1 | Request Time: 4ms | Backend: demoappv21-64498597c-r2lt9
Demoapp by vvoo! App Version: v2.1, Client IP: 127.0.0.6, Server Name: demoappv21-64498597c-r2lt9, Server IP: 10.244.2.39 ~
Frontend Proxy v1.1 | Request Time: 5ms | Backend: demoappv21-64498597c-r2lt9
Demoapp by vvoo! App Version: v2.1, Client IP: 127.0.0.6, Server Name: demoappv21-64498597c-r2lt9, Server IP: 10.244.2.39 ~
Frontend Proxy v1.1 | Request Time: 5ms | Backend: demoappv21-64498597c-r2lt9
Demoapp by vvoo! App Version: v2.1, Client IP: 127.0.0.6, Server Name: demoappv21-64498597c-r2lt9, Server IP: 10.244.2.39 ~
Frontend Proxy v1.1 | Request Time: 3ms | Backend: unknown
fault filter abortFrontend Proxy v1.1 | Request Time: 11ms | Backend: demoappv21-64498597c-r2lt9
Demoapp by vvoo! App Version: v2.1, Client IP: 127.0.0.6, Server Name: demoappv21-64498597c-r2lt9, Server IP: 10.244.2.39 ~
Frontend Proxy v1.1 | Request Time: 5ms | Backend: demoappv21-64498597c-r2lt9
Demoapp by vvoo! App Version: v2.1, Client IP: 127.0.0.6, Server Name: demoappv21-64498597c-r2lt9, Server IP: 10.244.2.39 ~
Frontend Proxy v1.1 | Request Time: 4ms | Backend: demoappv21-64498597c-r2lt9
Demoapp by vvoo! App Version: v2.1, Client IP: 127.0.0.6, Server Name: demoappv21-64498597c-r2lt9, Server IP: 10.244.2.39 ~
Frontend Proxy v1.1 | Request Time: 3ms | Backend: demoappv21-64498597c-29z6r
Demoapp by vvoo! App Version: v2.1, Client IP: 127.0.0.6, Server Name: demoappv21-64498597c-29z6r, Server IP: 10.244.1.51 ~
```

从结果可以看出，约 20% 的请求返回了错误（"fault filter abort"），其余请求正常返回。

## 故障注入的应用场景

1. **混沌工程实践**
   - 主动注入故障，验证系统的弹性和容错能力
   - 发现潜在的单点故障和级联故障风险

2. **超时和重试策略测试**
   - 通过延迟注入测试应用程序的超时设置是否合理
   - 验证重试机制是否正常工作

3. **断路器和降级策略验证**
   - 模拟服务不可用场景，测试断路器是否正确触发
   - 验证系统降级策略是否有效

4. **弹性设计验证**
   - 在受控环境中验证系统对各种故障的响应
   - 确保生产环境中的真实故障不会导致严重的服务中断

## 故障注入最佳实践

1. **从小比例开始**
   - 初始阶段使用较小的故障注入比例（如 5-10%）
   - 逐步增加比例，观察系统行为变化

2. **结合监控和告警**
   - 在进行故障注入测试时，密切监控系统指标
   - 设置适当的告警阈值，确保能及时发现异常

3. **测试环境先行**
   - 先在测试环境中进行故障注入实验
   - 确认无重大问题后，再考虑在生产环境中小规模测试

4. **有计划的测试**
   - 制定详细的测试计划，包括测试场景、预期结果和回滚策略
   - 提前通知相关团队，避免误判为真实故障