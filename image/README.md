## Desc：  
kubeadm部署kubernetes集群的镜像master：kubernetesMaster-v1.13.3.tar    node：kubernetesNode-v1.13.3.tar  
使用说明：  
由于默认使用的国外的镜像仓库，国内访问不到，所以先将镜像下载好，再安装，这两个包里面的镜像都是用于kubernetes-v1.13.3版本    
1、节点上面docker安装完成后下载镜像这两个包分别到master节点和node节点。  
master节点上面执行：docker load < kubernetesMaster-v1.13.3.tar   
node节点上面执行：docker load < kubernetesNode-v1.13.3.tar
