#!/bin/bash
# version: 1.1
# date: 20190603
# author: winthcloud
# description: build image and apply to the k8s cluster
basedir=${1}
method=${2}
harbor=${3}
SaveProjectDirName=${4}
ProjectName=${5}
Namespace=${6}
TAG=${7}
REPLICAS=${8}
CPU=${9}
MEMORY=${10}
kubeconf=${11}
containerPort=${12}
urlPath=${13}
k8sMaster=${14}
Dockerfile=${15}
ENV=${16}


[ -d "${basedir}/${SaveProjectDirName}" ] || mkdir ${basedir}/${SaveProjectDirName}
[ -z "$method" ] && echo "You need to select method" && exit 20
[ -z "$harbor" ] && echo "You need to input a harbor" && exit 20
[ -z "$SaveProjectDirName" ] && echo "You need to input a save project dir" && exit 20
[ -z "$ProjectName" ] && echo "You need to input ProjectName" && exit 20
[ -z "$Namespace" ] && echo "You need to input Namespace" && exit 20
[ -z "$REPLICAS" ] && echo "You need to input REPLICAS" && exit 20
[ -z "$CPU" ] && echo "You need to input cpu number" && exit 20
[ -z "$MEMORY" ] && echo "You need to input memory size" && exit 20
[ -z "$kubeconf" ] && echo "You need to input kubeconf" && exit 20
[ -z "$containerPort" ] && echo "You need to input containerPort" && exit 20
[ -z "$urlPath" ] && echo "You need to input urlpath" && exit 20
[ -z "$k8sMaster" ] && echo "You need to input k8sMaster" && exit 20

build_image(){
  if [ -z "${Dockerfile}" ]; then
      docker build -t ${harbor}/project/${ProjectName}:$TAG .
  else
      [ -z "${ENV}" ] && echo "variable ENV is null" && exit 20
      docker build -f ${Dockerfile} --build-arg ENV=${ENV} -t ${harbor}/project/${ProjectName}:$TAG .
  fi
  if [ "$?" -eq 0 ];then
    docker push ${harbor}/project/${ProjectName}:${TAG}
  else
    docker container rm -f $(docker container ls -aq)
    exit 10
  fi
  if [ "$?" -eq 0 ];then
     [ -f "${basedir}/${SaveProjectDirName}/tags" ] || touch ${basedir}/${SaveProjectDirName}/tags
     docker image rm ${harbor}/project/${ProjectName}:$TAG
     grep ${ProjectName}:${TAG} ${basedir}/${SaveProjectDirName}/tags || echo "${harbor}/project/${ProjectName}:${TAG}" >> ${basedir}/${SaveProjectDirName}/tags
  fi
}

search_image(){
    cat ${basedir}/${SaveProjectDirName}/tags | grep ${ProjectName}:${TAG}
    if [ $? -eq 0 ];then
       return 0
    else
       return 1
    fi
}

change_k8s_yaml(){
  cat > ${basedir}/${SaveProjectDirName}/deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: ${ProjectName}
  name: ${ProjectName}
  namespace: ${Namespace}
spec:
  replicas: ${REPLICAS}
  revisionHistoryLimit: 10
  selector:
    matchLabels:
      app: ${ProjectName}
  template:
    metadata:
      labels:
        app: ${ProjectName}
    spec:
      imagePullSecrets:
      - name: sxkj-harbor
      containers:
      - name: ${ProjectName}-service1
        image: ${harbor}/project/${ProjectName}:${TAG}
        imagePullPolicy: Always
        command: ["/bin/bash"]
        args: ["-c","java -jar water-service1-0.0.1-SNAPSHOT.jar &> /data/logs/electronic-hardware-chargepal/water-service1.log"]
        volumeMounts:
        - name: mysql-cred
          mountPath: "/projected-volume/conf/"
        - name: logs
          mountPath: /data/logs/electronic-hardware-chargepal/
        ports:
        - containerPort: ${containerPort}
          protocol: TCP
        livenessProbe:
          tcpSocket:
            port: ${containerPort}
          initialDelaySeconds: 50
          timeoutSeconds: 5
#        readinessProbe:
#          initialDelaySeconds: 50
#          successThreshold: 2
#          timeoutSeconds: 5
#          failureThreshold: 2
#          periodSeconds: 5
#          httpGet: 
#            path: ${urlPath}
#            port: ${containerPort}
        resources:
          limits:
            cpu: ${CPU}
            memory: ${MEMORY}
          requests:
            cpu: 2000m
            memory: 2048Mi
      - name: ${ProjectName}-service2
        image: ${harbor}/project/${ProjectName}:${TAG}
        imagePullPolicy: Always
        command: ["/bin/bash"]
        args: ["-c","java -jar water-service2-0.0.1-SNAPSHOT.jar &> /data/logs/electronic-hardware-chargepal/water-service2.log"]
        volumeMounts:
        - name: mysql-cred
          mountPath: "/projected-volume/conf/"
        - name: logs
          mountPath: /data/logs/electronic-hardware-chargepal/
        ports:
        - containerPort: 8402
          protocol: TCP
        livenessProbe:
          tcpSocket:
            port: 8402
          initialDelaySeconds: 50
          timeoutSeconds: 5
#        readinessProbe:
#          initialDelaySeconds: 50
#          successThreshold: 2
#          timeoutSeconds: 5
#          failureThreshold: 2
#          periodSeconds: 5
#          httpGet: 
#            path: /small/swagger-ui.html
#            port: 8402
        resources:
          limits:
            cpu: ${CPU}
            memory: ${MEMORY}
          requests:
            cpu: 2000m
            memory: 2048Mi
      - name: filebeat
        image: ${harbor}/app/filebeat:v6.6.1
        command:
        - /usr/share/filebeat/filebeat
        - -c
        - /filebeat/filebeat.yml
        - -path.home
        - /usr/share/filebeat
        - -path.config
        - /etc/filebeat
        volumeMounts:
        - name: logs
          mountPath: /logs
        - name: filebeat
          mountPath: /filebeat
      volumes:
      - name: mysql-cred
        projected:
          sources:
          - secret:
              name: ${ProjectName}-mysql
      - name: logs
        emptyDir: {}
      - name: filebeat
        configMap:
          name: filebeat-${ProjectName}
          items:
          - key: filebeat.yml
            path: filebeat.yml
EOF
}

upload_k8s_cluster(){
   kubectl --kubeconfig=/var/lib/jenkins/kubernetes/.kube/${kubeconf} apply -f ${basedir}/${SaveProjectDirName}/deployment.yaml --record=true
}

copy_yaml_to_cluster_node(){
    ssh root@${k8sMaster} "[ -d /opt/project/${SaveProjectDirName} ] || mkdir -pv /opt/project/${SaveProjectDirName}"
    scp -pr ${basedir}/${SaveProjectDirName}/* root@${k8sMaster}:/opt/project/${SaveProjectDirName}/
}

case ${method} in
update)
    build_image
    change_k8s_yaml
    upload_k8s_cluster
    copy_yaml_to_cluster_node
    ;;
rollback)
    search_image
    if [ $? -eq 0 ];then
        change_k8s_yaml
        upload_k8s_cluster
        copy_yaml_to_cluster_node
    else
        build_image
        change_k8s_yaml
        upload_k8s_cluster
        copy_yaml_to_cluster_node
    fi
    ;;
esac
