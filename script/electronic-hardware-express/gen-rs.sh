#!/bin/bash
# version: 1.2
# date: 20190506
# author: winthcloud
# description: generate svc and other resources and apply to the k8s cluster
basedir=${1}
SaveProjectDirName=${2}
ProjectName=${3}
Namespace=${4}
kubeconf=${5}
containerPort=${6}
nodePort=${7}
[ -z "$basedir" ] && echo "You need to input basedir" && exit 20
[ -z "$SaveProjectDirName" ] && echo "You need to input SaveProjectDirName" && exit 20
[ -z "$ProjectName" ] && echo "You need to input ProjectName" && exit 20
[ -z "$Namespace" ] && echo "You need to input Namespace" && exit 20
[ -z "$kubeconf" ] && echo "You need to input kubeconf" && exit 20
[ -z "$containerPort" ] && echo "You need to input containerPort" && exit 20
[ -d "${basedir}/${SaveProjectDirName}" ] || mkdir ${basedir}/${SaveProjectDirName}
cat > ${basedir}/${SaveProjectDirName}/confmap-secret.yaml << EOF
apiVersion: v1
kind: ConfigMap
data:
  filebeat.yml: |
    filebeat.prospectors:
    - type: log
      enabled: true
      paths:
        - /logs/*.log
      tags: ["${ProjectName}-prod"]
      multiline.pattern: '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}.\d{3}'  
      multiline.negate: true
      multiline.match: after
    
    filebeat.config.modules:
      path: \${path.config}/modules.d/*.yml
      reload.enabled: false
    
    setup.template.settings:
      index.number_of_shards: 3
    
    setup.kibana:
 
    output.logstash:
      hosts: ["logstash.sxkj.online:5044"]
    
    logging.level: info
    
    logging.to_files: true
    logging.files:
      path: /tmp
      name: filebeat.log
      keepfiles: 7
      permissions: 0644

metadata:
  name: filebeat-${ProjectName}
  namespace: ${Namespace}
  
  
---
# # ------------------- Mysql Config ------------------- #
apiVersion: v1
kind: Secret
metadata:
  name: ${ProjectName}-mysql
  namespace: ${Namespace}
type: Opaque
data:
  config.ini: |
    W2RzXQpwb3J0ID0gMzMwNgpob3N0ID0gMTI3LjAuMC4xCnVzZXIgPSByb290CnB3ZCA9IHBhc3N3b3JkCmRiID0gZGF0YWJhc2VuYW1lCm1heF9pZGxlX3RpbWUgPSAxODAwCg==
EOF

if [ ! -z "$nodePort" ];then
cat > ${basedir}/${SaveProjectDirName}/service.yaml <<EOF
# # ------------------- Service ------------------- #

kind: Service
apiVersion: v1
metadata:
  labels:
    app: ${ProjectName}
  name: ${ProjectName}
  namespace: ${Namespace}
spec:
  type: NodePort
  ports:
    - port: ${containerPort}
      targetPort: ${containerPort}
      nodePort: ${nodePort}
  selector:
    app: ${ProjectName}-service
EOF
else
cat > ${basedir}/${SaveProjectDirName}/service.yaml <<EOF
# # ------------------- Service ------------------- #

kind: Service
apiVersion: v1
metadata:
  labels:
    app: ${ProjectName}
  name: ${ProjectName}
  namespace: ${Namespace}
spec:
  ports:
    - port: ${containerPort}
      targetPort: ${containerPort}
  selector:
    app: ${ProjectName}-service
EOF
fi



upload_k8s_cluster(){
   kubectl --kubeconfig=/var/lib/jenkins/kubernetes/.kube/${kubeconf} apply -f ${basedir}/${SaveProjectDirName}/confmap-secret.yaml --record=true
   kubectl --kubeconfig=/var/lib/jenkins/kubernetes/.kube/${kubeconf} apply -f ${basedir}/${SaveProjectDirName}/service.yaml --record=true
}

upload_k8s_cluster
