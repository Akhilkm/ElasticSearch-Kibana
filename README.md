# ElasticSearch Cluster on AKS


**Tested on Azure, This deployment will work in any other cloud but have to change the configurations for storageclass and loadbalancer configurations**
**This deployment using ES version 6.8.0, will not support version 7.x.x**

[kudos](https://medium.com/faun/https-medium-com-thakur-vaibhav23-ha-es-k8s-7e655c1b7b61)

[help](https://www.datadoghq.com/blog/elasticsearch-game-day/)

[readonlyrest-docs](https://github.com/beshu-tech/readonlyrest-docs/blob/master/elasticsearch.md)

## Current software

* Alpine Linux 3.8
* OpenJDK JRE 8u171
* Elasticsearch 6.8.0 -- 6.8.0

## Kubernetes Cluster Requirement

* cluster of 3 worker nodes (HA Configuration)
* medium / high IOPS Required for the vm type
* 2vcpu and 8 GB RAM for each worker ndoes
* premium Storageclass needed for better performance


## ES Cluster Features

* High Available (HA) Cluster on Kubernetes
* Self Healing Configuration for all nodes
* anytime can scale the cluster size (both horizontal and vertical)
* Authentication and Authorisation enabled with custom configuration and plugins
* The default cluster have the following components (can be increase the number anytime without downtime)
	* Three master nodes
 	* Three data nodes
	* Two client nodes
	* One ES-HQ server
	* One Kibana Server
	* Three APM server



## Authentication for ElasticSearch and Kibana

```
ES version 6.8.0 Docker image have plugin readonlyrest plugin, and so youy can enable the authentication for elasticsearch with the following environment Variables
```

This kubernetes deployment by default enabling the authetication for elasticsearch and kibana. If you don't need authetication you can simply remove the `AUTH_CONFIG` environment variable.

These are the default Credentials for the deployment until and unless you remove the `AUTH_CONFIG` environment variable.

The Usernames are hardcoded but you can override this credentials (only passwords) by updating these environment variables from Configmap (I already gave it as an example in the deployment part) or from secrets in kubernetes


**Note: API Server, Kibana Server and ES-HQ Server need kibanAdmin credentials for accessing the cluster**


| User Name | Variable Name | Default Value | Description |
|---------------|---------------|---------------|---------------|
| kibanAdmin | KIBANA_ADMIN_PASSWORD | Admin@Kibana | Have full permission on the ES cluster and kibana dashboard |
| kibanaUser | KIBANA_RO_PASSWORD | Ro@Kibana | Have readonly access on ES cluster and kibana dashboard |
| LogAdmin | PUSHLOG_PASSWORD | Push2ES | Password for elasticsearch authetication (used by log shippers) |


**Note : For Kibana Auth Configiuration while deploying, you have to configure User : kibanAdmin and Pass : KIBANA_ADMIN_PASSWORD**


**Note:** `x-pack-ml` module is forcibly disabled as it's not supported on Alpine Linux.

## Kubernetes Deployment 

**Note: These following environment and its default values are giving below, it is customised for dockerized deployment in K8s but will degrade the performance (MEMORY_LOCK false)**

```
MEMORY_LOCK false
DISCOVERY_SERVICE elasticsearch-discovery
```


kubernetes issue : [Not support new ES version](https://hub.helm.sh/charts/stable/elasticsearch)

**Run these commands from `Kubernetes-Deployment` Folder**

### Create Namespace for Elasticsearch Deployment

```
kubectl apply -f es-namespace.yaml
```

### Configure Credentials

```
kubectl apply -f ElasticSearch/es-auth-configmap.yaml
```

### Deploy master nodes

```
kubectl apply -f ElasticSearch/es-master-deployment.yaml
kubectl apply -f ElasticSearch/es-master-service.yaml
kubectl -n elasticsearch get pods
```

### Deploy data nodes

```
kubectl apply -f ElasticSearch/es-data-storageclass.yaml
kubectl get storageclass
kubectl apply -f ElasticSearch/es-data-deployment.yaml
kubectl apply -f ElasticSearch/es-data-service.yaml
kubectl -n elasticsearch get pods
```

### Deploy client nodes

```
kubectl apply -f ElasticSearch/es-client-deployment.yaml
kubectl apply -f ElasticSearch/es-client-service.yaml
kubectl -n elasticsearch get pods
```

ElasticSearch can access on this url : `http://<<es_client_loadbalancer_IPAddress>>:9200`


### Deploy Elastic HQ (Monitoring tool)

**Update the ConfigMap : `es-hq-configmap.yaml` with the basic-auth username and password**

```
kubectl apply -f ES-HQ/es-hq-configmap.yaml
kubectl apply -f ES-HQ/es-hq-deployment.yaml
kubectl apply -f ES-HQ/es-hq-service.yaml
kubectl -n elasticsearch get pods
```

Elastic HQ can access on this url : `http://<<es_HQ_loadbalancer_IPAddress>>`

### Deploy Kibana Server

```
kubectl -n elasticsearch create configmap kibana-config-cm --from-file=kibana/kibana.yml
kubectl apply -f kibana/kibana-deployment.yaml
kubectl apply -f kibana/kibana-service.yaml
kubectl -n elasticsearch get pods
```

kibana can access on this url : `http://<<kibana_loadbalancer_IPAddress>>/app/kibana`


### Deploy Elastic APM Server

```
kubectl -n elasticsearch create configmap apm-server-cm --from-file=ES-APM/apm-server.yml
kubectl apply -f ES-APM/es-apm-deployment.yaml
kubectl apply -f ES-APM/es-apm-service.yaml
kubectl -n elasticsearch get pods
```

Elastic APM can access on this url : `http://<<es_APM_loadbalancer_IPAddress>>`

### Check the services, pods, pvc and pv
```
kubectl -n elasticsearch get pods
kubectl -n elasticsearch get services
kubectl -n elasticsearch get pvc
kubectl get pv
```


## Scaling Considerations

### client nodes

We can deploy autoscalers for our client nodes depending upon our CPU thresholds. A sample HPA for client node might look something like this:

**NOTE : you have to install and configure matrics in your cluster**

```
apiVersion: autoscaling/v1
kind: HorizontalPodAutoscaler
metadata:
  name: es-client
  namespace: elasticsearch
spec:
  maxReplicas: 5
  minReplicas: 2
  scaleTargetRef:
    apiVersion: extensions/v1beta1
    kind: Deployment
    name: es-client
  targetCPUUtilizationPercentage: 80
```

Whenever the autoscaler will kick in, we can watch the new client-node pods being added to the cluster, by observing the logs of any of the master-node pods.

### data nodes

In case of Data-Node Pods all we have to do it increase the number of replicas using the K8 Dashboard or GKE console. The newly created data node will be automatically added to the cluster and start replicating data from other nodes.

### master nodes

Master-Node Pods do not require autoscaling as they only store cluster-state information but in case you want to add more data nodes make sure there are no even number of master nodes in the cluster also the environment variable NUMBER_OF_MASTERS is updated accordingly.



## PVC Resizing Configuration

[here](https://kubernetes.io/blog/2018/07/12/resizing-persistent-volumes-using-kubernetes/)

1. Delete all the pods which are using pvc (delete the StatefulSet)
2. edit all pvc with as follows

```
kubectl -n elasticsearch edit  pvc storage-es-data-0
```

update the storage entry.

3. redeploy the `StatefulSet`



## The LOG Battle: Logstash and Fluentd

* source data processing pipeline
  * Logstash
  * Fluentd
* lightweight shippers
  * Filebeat
  * Fluentbit

[here](https://medium.com/tensult/the-log-battle-logstash-and-fluentd-c65f2f7c24b4)

### filebeat

[installation 1](https://www.elastic.co/guide/en/beats/filebeat/current/filebeat-installation.html)

[installation 2](https://crunchify.com/setup-guide-install-configure-filebeat/)

[configuration](https://www.elastic.co/guide/en/beats/filebeat/5.1/filebeat-configuration-details.html)


## Run

### Attention

* In order for `bootstrap.mlockall` to work, `ulimit` must be allowed to run in the container. Run with `--privileged` to enable this.
* [Multicast discovery is no longer built-in](https://www.elastic.co/guide/en/elasticsearch/reference/2.3/breaking_20_removed_features.html#_multicast_discovery_is_now_a_plugin)

Ready to use node for cluster `elasticsearch-default`:

```
docker run --name elasticsearch \
	--detach \
	--privileged \
	--volume /path/to/data_folder:/data \
        akhilrajmailbox/elasticsearch:elasticsearch-6.8.0
```

Ready to use node for cluster `myclustername`:

```
docker run --name elasticsearch \
	--detach \
	--privileged \
	--volume /path/to/data_folder:/data \
	-e CLUSTER_NAME=myclustername \
        akhilrajmailbox/elasticsearch:elasticsearch-6.8.0
```

Ready to use node for cluster `elasticsearch-default`, with 8GB heap allocated to Elasticsearch:

```
docker run --name elasticsearch \
	--detach \
	--privileged \
	--volume /path/to/data_folder:/data \
	-e ES_JAVA_OPTS="-Xms8g -Xmx8g" \
        akhilrajmailbox/elasticsearch:elasticsearch-6.8.0
```

Ready to use node with plugins (x-pack and repository-gcs) pre installed. Already installed plugins are ignored:

```
docker run --name elasticsearch \
	--detach \
	--privileged \
	--volume /path/to/data_folder:/data \
	-e ES_JAVA_OPTS="-Xms8g -Xmx8g" \
	-e ES_PLUGINS_INSTALL="repository-gcs,x-pack" \
        akhilrajmailbox/elasticsearch:elasticsearch-6.8.0
```

**Master-only** node for cluster `elasticsearch-default`:

```
docker run --name elasticsearch \
	--detach \
	--privileged \
	--volume /path/to/data_folder:/data \
	-e NODE_DATA=false \
	-e HTTP_ENABLE=false \
        akhilrajmailbox/elasticsearch:elasticsearch-6.8.0
```

**Data-only** node for cluster `elasticsearch-default`:
```
docker run --name elasticsearch \
	--detach --volume /path/to/data_folder:/data \
	--privileged \
	-e NODE_MASTER=false \
	-e HTTP_ENABLE=false \
        akhilrajmailbox/elasticsearch:elasticsearch-6.8.0
```

**Data-only** node for cluster `elasticsearch-default` with shard allocation awareness:

```
docker run --name elasticsearch \
	--detach --volume /path/to/data_folder:/data \
        --volume /etc/hostname:/dockerhost \
	--privileged \
	-e NODE_MASTER=false \
	-e HTTP_ENABLE=false \
    -e SHARD_ALLOCATION_AWARENESS=dockerhostname \
    -e SHARD_ALLOCATION_AWARENESS_ATTR="/dockerhost" \
        akhilrajmailbox/elasticsearch:elasticsearch-6.8.0
```

**Client-only** node for cluster `elasticsearch-default`:

```
docker run --name elasticsearch \
	--detach \
	--privileged \
	--volume /path/to/data_folder:/data \
	-e NODE_MASTER=false \
	-e NODE_DATA=false \
        akhilrajmailbox/elasticsearch:elasticsearch-6.8.0
```

I also make available special images and instructions for [AWS EC2](https://github.com/pires/docker-elasticsearch-aws) and [Kubernetes](https://github.com/pires/docker-elasticsearch-kubernetes).

### Environment variables

This image can be configured by means of environment variables, that one can set on a `Deployment`.

* [CLUSTER_NAME](https://www.elastic.co/guide/en/elasticsearch/reference/current/important-settings.html#cluster.name)
* [NODE_NAME](https://www.elastic.co/guide/en/elasticsearch/reference/current/important-settings.html#node.name)
* [NODE_MASTER](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-node.html#master-node)
* [NODE_DATA](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-node.html#data-node)
* [NETWORK_HOST](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-network.html#network-interface-values)
* [HTTP_ENABLE](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-http.html#_settings_2)
* [HTTP_CORS_ENABLE](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-http.html#_settings_2)
* [HTTP_CORS_ALLOW_ORIGIN](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-http.html#_settings_2)
* [NUMBER_OF_MASTERS](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-discovery-zen.html#master-election)
* [MAX_LOCAL_STORAGE_NODES](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-node.html#max-local-storage-nodes)
* [ES_JAVA_OPTS](https://www.elastic.co/guide/en/elasticsearch/reference/current/heap-size.html)
* [ES_PLUGINS_INSTALL](https://www.elastic.co/guide/en/elasticsearch/plugins/current/installation.html) - comma separated list of Elasticsearch plugins to be installed. Example: `ES_PLUGINS_INSTALL="repository-gcs,x-pack"`
* [SHARD_ALLOCATION_AWARENESS](https://www.elastic.co/guide/en/elasticsearch/reference/current/allocation-awareness.html#CO287-1)
* [SHARD_ALLOCATION_AWARENESS_ATTR](https://www.elastic.co/guide/en/elasticsearch/reference/current/allocation-awareness.html#CO287-1)
* [MEMORY_LOCK](https://www.elastic.co/guide/en/elasticsearch/reference/current/important-settings.html#bootstrap.memory_lock) - memory locking control - enable to prevent swap (default = `true`) .
* DISCOVERY_SERVICE (default = elasticsearch-discovery)
* [REPO_LOCATIONS](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-snapshots.html#_shared_file_system_repository) - list of registered repository locations. For example `"/backup"` (default = `[]`). The value of REPO_LOCATIONS is automatically wrapped within an `[]` and therefore should not be included in the variable declaration. To specify multiple repository locations simply specify a comma separated string for example `"/backup", "/backup2"`.
* [PROCESSORS](https://github.com/elastic/elasticsearch-definitive-guide/pull/679/files) - allow elasticsearch to optimize for the actual number of available cpus (must be an integer - default = 1)

### Backup
Mount a shared folder (for example via NFS) to `/backup` and make sure the `elasticsearch` user
has write access. Then, set the `REPO_LOCATIONS` environment variable to `"/backup"` and create
a backup repository:

`backup_repository.json`:
```
{
  "type": "fs",
  "settings": {
    "location": "/backup",
    "compress": true
  }
}
```

```bash
curl -XPOST http://<container_ip>:9200/_snapshot/nas_repository -d @backup_repository.json`
```

Now, you can take snapshots using:

```bash
curl -f -XPUT "http://<container_ip>:9200/_snapshot/nas_repository/snapshot_`date --utc +%Y_%m_%dt%H_%M`?wait_for_completion=true"
```



## azure blob storage and snapshots

For configuring the Azure blobe storage as snapshot registry, first create the blobe storage account in azure and then you have to configure the following environment variable for the es deployment


variable name	|	default value	| description
---------------------|---------------------|---------------------
AZURE_REPOSITORY_CONFIG	| -	| This value should be "true" to enable the snapshots |
AZURE_REPOSITORY_ACCOUNT_NAME	|	-	|	configure the blob storage name |
AZURE_REPOSITORY_ACCOUNT_KEY	|	-	|	configure the key1 or key2 value here |



### register the snapshot repository

**note : i am using the sub container name `backup-container` in here, you can give any name here but you have to create the container in the storage account before starting the elasticsearch**

```
curl -XPUT 'http://192.168.0.12:9200/_snapshot/azure_backup' -H 'Content-Type: application/json' -d '{
  "type": "azure",
  "settings": {
    "account": "default",
    "container": "backup-container",
    "base_path": "backups",
    "chunk_size": "32MB",
    "compress": true
  }
}'
```

### create a sample snapshot

```
curl -XPUT 'http://@192.168.0.12:9200/_snapshot/azure_backup/snapshot_1' -H 'Content-Type: application/json' -d '{ "indices":"*","include_global_state":false }'
```


## Backup and Restore Steps

### Backup

* Install plugin:-

```
sudo ES_PATH_CONF=/etc/elasticsearch/es-node-2 /usr/share/elasticsearch/bin/elasticsearch-plugin install repository-azure
```

* change the configuration:-

```
sudo nano /etc/elasticsearch/es-node-2/elasticsearch.yml
cloud.azure.storage.default.account: xxxxxxxxxxx
cloud.azure.storage.default.key: xxxxxx
```

* Restart ES Service:-

```
sudo systemctl restart es-node-2_elasticsearch.service
```

* create Repo:-

```
curl -XPUT 'http://localhost:9200/_snapshot/azurebackup' -H 'Content-Type: application/json' -d '{ "type": "azure", "settings": { "container": "elasticsearch-snapshots", "base_path": "sunbirddevtele"} }'
```

* create Snapshot:-

```
curl -XPUT 'http://localhost:9200/_snapshot/azurebackup/snapshot_1' -H 'Content-Type: application/json' -d '{ "indices":"*","include_global_state":false }'
```

* check status of backup:-

```
curl -XGET 'http://localhost:9200/_snapshot/azurebackup/_all'
```


### Restore

* Install plugin:-

```
sudo ES_PATH_CONF=/etc/elasticsearch/es-node-2 /usr/share/elasticsearch/bin/elasticsearch-plugin install repository-azure
```

* change the configuration:-

```
sudo nano /etc/elasticsearch/es-node-2/elasticsearch.yml
cloud.azure.storage.default.account: xxxxxxxxxxx
cloud.azure.storage.default.key: xxxxxx
```

* Restart ES Service:- 

```
sudo systemctl restart es-node-1_elasticsearch.service
```

* create Repo:-

```
curl -XPUT 'http://localhost:9200/_snapshot/azurebackup' -H 'Content-Type: application/json' -d '{ "type": "azure", "settings": { "container": "elasticsearch-snapshots", "base_path": "sunbirddevtele"} }'
```

* Delete unwanted indices:- 

```
curl -XDELETE http://localhost:9200/_all
```

* Restore from snapshot:-

```
curl -XPOST 'http://localhost:9200/_snapshot/azurebackup/snapshot_1/_restore'
```


### Reference links ::

[snapshots-restore](https://github.com/project-sunbird/sunbird-devops/wiki/elasticsearch-backup-and-restore-for-telemetry-and-composite-search-to-azure-blob)

[es-azure snapshots plugin](https://www.elastic.co/guide/en/elasticsearch/plugins/6.8/repository-azure.html)

[es-azure plugin description](https://www.elastic.co/guide/en/elasticsearch/plugins/7.4/repository-azure-repository-settings.html)

[blob-storage and snapshots 1](https://azure.microsoft.com/en-in/blog/archive-elasticsearch-indices-to-azure-blob-storage-using-the-azure-cloud-plugin/)

[blob-storage and snapshots 2](https://stackoverflow.com/questions/54113059/elasticsearch-snapshot-creation-understanding-how-where-to-store-them-to)


