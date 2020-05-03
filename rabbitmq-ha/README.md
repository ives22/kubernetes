

# 1 存储卷准备

## 1.1 准备nfs

```shell
1.安装nfs
# yum -y install nfs-utils
2.创建nfs共享目录
# mkdir /data/volumes/rabbitmq -p
3.编辑配置文件
# vim /etc/exports
/data/volumes/rabbitmq 10.10.10.0/24(rw,no_root_squash)
4.启动nfs
# systemctl start rpcbind && systemctl enable rpcbind
# systemctl start nfs && systemctl enable nfs
```



# 2 master节点

```shell
修改rabbitmq-pv.yaml
# vim rabbitmq-pv.yaml
  nfs:
    server: 10.10.10.21 #这里请写nfs服务器的ip
    path: /data/volumes/rabbitmq
    
建立持久卷
# kubectl apply -f rabbitmq-pv.yaml 

查看持久卷是否创建成功
# kubectl get pv
```



```shell
创建名称空间
# kubectl create namespace rabbitmq

创建pvc
# kubectl apply -f rabbitmq-pvc.yaml 

创建configmap
# kubectl apply -f rabbitmq-configmap.yaml 

创建rbac
# kubectl apply -f rabbitmq-rbac.yaml 

创建statefulset
# kubectl apply -f rabbitmq-statefulset.yaml 

创建service
# kubectl apply -f rabbitmq-service.yaml 

验证
# kubectl get pods -n rabbitmq
NAME            READY   STATUS    RESTARTS   AGE
rabbitmq-ha-0   1/1     Running   0          46s
rabbitmq-ha-1   1/1     Running   0          44s
rabbitmq-ha-2   1/1     Running   0          41s

# kubectl get svc -n rabbitmq
NAME       TYPE       CLUSTER-IP       EXTERNAL-IP   PORT(S)                          AGE
rabbitmq   NodePort   10.101.152.206   <none>        15672:31672/TCP,5672:30672/TCP   9m11s
```



登陆验证：`节点IP:31672`        账户密码：guest/guest

