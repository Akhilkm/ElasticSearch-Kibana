#!/bin/sh

echo "Starting Elasticsearch ${ES_VERSION}"

BASE=/elasticsearch

# Allow for memlock if enabled
if [ "${MEMORY_LOCK}" == "true" ]; then
    ulimit -l unlimited
fi

# Set a random node name if not set
if [ -z "${NODE_NAME}" ]; then
    NODE_NAME="$(uuidgen)"
fi

# Create a temporary folder for Elasticsearch ourselves
# ref: https://github.com/elastic/elasticsearch/pull/27659
export ES_TMPDIR="$(mktemp -d -t elasticsearch.XXXXXXXX)"

# Prevent "Text file busy" errors
sync

if [ ! -z "${ES_PLUGINS_INSTALL}" ]; then
    OLDIFS="${IFS}"
    IFS=","
    for plugin in ${ES_PLUGINS_INSTALL}; do
        if ! "${BASE}"/bin/elasticsearch-plugin list | grep -qs ${plugin}; then
            until "${BASE}"/bin/elasticsearch-plugin install --batch ${plugin}; do
                echo "Failed to install ${plugin}, retrying in 3s"
                sleep 3
            done
        fi
    done
    IFS="${OLDIFS}"
fi

if [ ! -z "${AZURE_REPOSITORY_CONFIG}" ]; then
    if [ ! -z "${AZURE_REPOSITORY_ACCOUNT_NAME}" ] && [ ! -z "${AZURE_REPOSITORY_ACCOUNT_KEY}" ] ; then
echo "Configuring plugin : repository-azure for ES version ${ES_VERSION}"
yes | bin/elasticsearch-plugin install file:///tmp/repository-azure-${ES_VERSION}.zip
rm -rf /tmp/repository-azure-${ES_VERSION}.zip

echo -e "\ncloud.azure.storage.default.account: \${AZURE_REPOSITORY_ACCOUNT_NAME}" >> $BASE/config/elasticsearch.yml
echo -e "\ncloud.azure.storage.default.key: \${AZURE_REPOSITORY_ACCOUNT_KEY}" >> $BASE/config/elasticsearch.yml
    else
        echo "AZURE_REPOSITORY_CONFIG is there but AZURE_REPOSITORY_ACCOUNT_NAME or/and AZURE_REPOSITORY_ACCOUNT_KEY is/are missing..!"
    fi
fi

if [ ! -z "${AUTH_CONFIG}" ] ; then
# readonlyrest configuration
echo "Configuring readonlyrest for ES version ${ES_VERSION}"
yes | bin/elasticsearch-plugin install file:///tmp/readonlyrest-1.18.7_es${ES_VERSION}.zip
rm -rf /tmp/readonlyrest-1.18.7_es${ES_VERSION}.zip

cat << EOF > /elasticsearch/config/readonlyrest.yml
readonlyrest:
    enable: true
    response_if_req_forbidden: <h1>Forbidden</h1>
    access_control_rules:
    - name: Kibana Server (we trust this server side component, full access granted via HTTP authentication, this is the user have admin privilege on kibana)
      auth_key: kibanAdmin:${KIBANA_ADMIN_PASSWORD}
      type: allow
    - name: Kibana Server (we trust this server side component, full access granted via HTTP authentication, this is the user for elasticsearch and kibana server connection)
      auth_key: kibanaUser:${KIBANA_RO_PASSWORD}
      kibana_access: ro
      type: allow
    - name: fluentd Client (this user can write and create its own indices, this is the user for elasticsearch and fluentd connection)
      auth_key: LogAdmin:${PUSHLOG_PASSWORD}
      type: allow
      actions: ["cluster:monitor/*","indices:data/read/*","indices:data/write/*","indices:admin/template/*","indices:admin/create"]
      indices: ["*"]
EOF
fi


if [ ! -z "${SHARD_ALLOCATION_AWARENESS_ATTR}" ]; then
    # this will map to a file like  /etc/hostname => /dockerhostname so reading that file will get the
    #  container hostname
    if [ -f "${SHARD_ALLOCATION_AWARENESS_ATTR}" ]; then
        ES_SHARD_ATTR="$(cat "${SHARD_ALLOCATION_AWARENESS_ATTR}")"
    else
        ES_SHARD_ATTR="${SHARD_ALLOCATION_AWARENESS_ATTR}"
    fi

    NODE_NAME="${ES_SHARD_ATTR}-${NODE_NAME}"
    echo "node.attr.${SHARD_ALLOCATION_AWARENESS}: ${ES_SHARD_ATTR}" >> $BASE/config/elasticsearch.yml

    if [ "$NODE_MASTER" == "true" ]; then
        echo "cluster.routing.allocation.awareness.attributes: ${SHARD_ALLOCATION_AWARENESS}" >> "${BASE}"/config/elasticsearch.yml
    fi
fi

export NODE_NAME=${NODE_NAME}

# remove x-pack-ml module
rm -rf /elasticsearch/modules/x-pack/x-pack-ml
rm -rf /elasticsearch/modules/x-pack-ml

# Run
if [[ $(whoami) == "root" ]]; then
    if [ ! -d "/data/data/nodes/0" ]; then
        echo "Changing ownership of /data folder"
        chown -R elasticsearch:elasticsearch /data
    fi
    exec su-exec elasticsearch $BASE/bin/elasticsearch $ES_EXTRA_ARGS
else
    # The container's first process is not running as 'root', 
    # it does not have the rights to chown. However, we may
    # assume that it is being ran as 'elasticsearch', and that
    # the volumes already have the right permissions. This is
    # the case for Kubernetes, for example, when 'runAsUser: 1000'
    # and 'fsGroup:100' are defined in the pod's security context.
    "${BASE}"/bin/elasticsearch ${ES_EXTRA_ARGS}
fi
