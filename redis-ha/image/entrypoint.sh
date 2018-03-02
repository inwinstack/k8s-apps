#!/bin/bash

function echo_warn(){
    echo -e "\033[33m$1\033[0m"
}

function echo_info(){
    echo -e "\033[36m$1\033[0m"
}

function echo_error(){
    echo -e "\033[31m$1\033[0m"
}

function log_info(){
    time=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "\033[36m$time  -  $1\033[0m"
}

function log_warn(){
    time=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "\033[33m$time  - [WARNNING] $1\033[0m"
}

function log_error(){
    time=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "\033[31m$time  - [ERROR] $1\033[0m"
}

function master_launcher(){

    echo_info "************************************************************************************"
    echo_info "\t\t\t                                "
    echo_info "\t\t\tMaster Port  : $MASTER_PORT     "
    echo_info "\t\t\tSentinel HOST: $SENTINEL_HOST   "
    echo_info "\t\t\tSentinel Port: $SENTINEL_PORT   "
    echo_info "\t\t\t                                "
    echo_info "************************************************************************************"

    # 循环10次
    guard=0
    while test $guard -lt 10 ; do
        SENTINEL_IP=$(nslookup $SENTINEL_HOST | grep 'Address' | awk '{print $3}')
        MASTER_IP=$(redis-cli -h $SENTINEL_IP -p $SENTINEL_PORT --csv SENTINEL get-master-addr-by-name mymaster | tr ',' ' ' | cut -d' ' -f1)
        if [[ -n $MASTER_IP && $MASTER_IP != "ERROR" ]] ; then
            MASTER_IP="${MASTER_IP//\"}"
            redis-cli -h $MASTER_IP -p $MASTER_PORT INFO
            if test "$?" == "0" ; then
                sed -i "s/%master-ip%/$MASTER_IP/" /config/redis/slave.conf
                sed -i "s/%master-port%/$MASTER_PORT/" /config/redis/slave.conf
                PERSISTENT_PATH="/data/redis/master"
                sed -i "s|%persistent_path%|${PERSISTENT_PATH}|" /config/redis/slave.conf
                THIS_IP=$(hostname -i)
                echo "slave-announce-ip $THIS_IP" >> /config/redis/slave.conf
                echo "slave-announce-port $MASTER_PORT" >> /config/redis/slave.conf
                redis-server /config/redis/slave.conf --protected-mode no
                break
            else
                log_error "Can not connect to Master . Waiting...."
            fi
        fi
        let guard++
        if test $guard -ge 10 ; then
            log_info "Starting master ...."
            redis-server /config/redis/master.conf --protected-mode no
            break
        fi
        sleep 2
    done
}

function slave_launcher(){

    echo_info "************************************************************************************"
    echo_info "\t\t\t                                "
    echo_info "\t\t\tMaster Host  : $MASTER_HOST     "
    echo_info "\t\t\tMaster Port  : $MASTER_PORT     "
    echo_info "\t\t\tSentinel HOST: $SENTINEL_HOST   "
    echo_info "\t\t\tSentinel Port: $SENTINEL_PORT   "
    echo_info "\t\t\t                                "
    echo_info "************************************************************************************"

    while true; do
        SENTINEL_IP=$(nslookup ${SENTINEL_HOST} | grep 'Address' | awk '{print $3}')
        MASTER_IP=$(redis-cli -h ${SENTINEL_IP} -p ${SENTINEL_PORT} --csv SENTINEL get-master-addr-by-name mymaster | tr ',' ' ' | cut -d' ' -f1)
        if [[ -n ${MASTER_IP} ]] && [[ ${MASTER_IP} != "ERROR" ]] ; then
            MASTER_IP="${MASTER_IP//\"}"
        else
            sleep 2
            continue
        fi
        redis-cli -h ${MASTER_IP} -p ${MASTER_PORT} INFO
        if [[ "$?" == "0" ]]; then
            break
        fi

        log_error "Can not connect to Master .  Waiting..."
        sleep 5
    done

    THIS_IP=$(hostname -i)

    sed -i "s/%master-ip%/${MASTER_IP}/" /config/redis/slave.conf
    sed -i "s/%master-port%/${MASTER_PORT}/" /config/redis/slave.conf
    PERSISTENT_PATH="/data/redis/slave"
    sed -i "s|%persistent_path%|${PERSISTENT_PATH}|" /config/redis/slave.conf

    echo "slave-announce-ip ${THIS_IP}" >> /config/redis/slave.conf
    echo "slave-announce-port $MASTER_PORT" >> /config/redis/slave.conf

    redis-server  /config/redis/slave.conf --protected-mode no
}

function sentinel_launcher(){

    log_info "Starting sentinels..."
    echo -e "\n"

    echo_info "************************************************************************************"
    echo_info "\t\t\t                                "
    echo_info "\t\t\tMaster Host  : $MASTER_HOST     "
    echo_info "\t\t\tMaster Port  : $MASTER_PORT     "
    echo_info "\t\t\tSentinel SVC : $SENTINEL_SVC    "
    echo_info "\t\t\tSentinel Port: $SENTINEL_PORT   "
    echo_info "\t\t\t                                "
    echo_info "************************************************************************************"

    MASTER_IP=""
    while true; do
        index=0
        while true; do
            let index++
            IP_ARRAY=$(nslookup $SENTINEL_SVC | grep 'Address' |awk '{print $3}' )
            for IP in $IP_ARRAY ;
            do
                MASTER_IP=$(redis-cli -h ${IP} -p ${SENTINEL_PORT} --csv SENTINEL get-master-addr-by-name mymaster | tr ',' ' ' | cut -d' ' -f1)
                if [[ -n ${MASTER_IP} &&  ${MASTER_IP} != "ERROR" ]] ; then
                    MASTER_IP="${MASTER_IP//\"}"
                fi
                redis-cli -h ${MASTER_IP} -p ${MASTER_PORT} INFO
                if test "$?" == "0" ; then
                    break 3
                fi
                log_error "Sentinel IP:${IP}  Connecting to master failed.  Waiting..."
            done
            if test $index -ge 10 ; then
                log_info "Could not find the Sentinel ,Try to connenct the master directly!..."
                MASTER_IP=$(nslookup $MASTER_HOST | grep 'Address' | awk '{print $3}')
                redis-cli -h ${MASTER_IP} -p ${MASTER_PORT} INFO
                if test "$?" == "0" ; then
                    break 2
                else
                    index=0
                fi
                log_error "Sentinel IP:${IP}  Master IP: ${MASTER_IP}  Connecting to master failed.  Waiting..."
            fi
        done
    done

    log_info "Master: $MASTER_IP"

    sentinel_conf=/config/redis/sentinel.conf

    echo "port $SENTINEL_PORT" >> ${sentinel_conf}
    echo "sentinel monitor mymaster ${MASTER_IP} ${MASTER_PORT} 2" >> ${sentinel_conf}
    echo "sentinel down-after-milliseconds mymaster 30000" >> ${sentinel_conf}
    echo "sentinel failover-timeout mymaster 180000" >> ${sentinel_conf}
    echo "sentinel parallel-syncs mymaster 1" >> ${sentinel_conf}
    echo "bind $(hostname -i) 127.0.0.1" >> ${sentinel_conf}

    redis-sentinel ${sentinel_conf} --protected-mode no
}

function cluster_launcher(){
    log_info "Starting cluster ..."

    THIS_IP=$(hostname -i)
    echo "port ${REDIS_PORT}" >> /config/redis/cluster.conf
    echo "bind $(hostname -i) 127.0.0.1 " >> /config/redis/cluster.conf

    echo "slave-announce-ip ${THIS_IP}" >> /config/redis/cluster.conf
    echo "slave-announce-port ${REDIS_PORT}" >> /config/redis/cluster.conf

    echo "cluster-announce-ip ${THIS_IP}" >> /config/redis/cluster.conf
    echo "cluster-announce-port ${REDIS_PORT}" >> /config/redis/cluster.conf

    redis-server /config/redis/cluster.conf --protected-mode no
}

function cluster_ctrl_launcher(){
    echo_info "************************************************************************************"
    echo_info "\t\t\t                                "
    echo_info "\t\t\tCLUSTER_SVC  : $CLUSTER_SVC     "
    echo_info "\t\t\tAPI_SERVER_ADDR   : $API_SERVER_ADDR   "
    echo_info "\t\t\tREDIS_CLUSTER_SLAVE_QUANTUM  : $REDIS_CLUSTER_SLAVE_QUANTUM     "
    echo_info "\t\t\t                                "
    echo_info "************************************************************************************"

    gem install --local /rdoc-600.gem
    gem install --local /redis-401.gem

    while true ; do
        Listener=$(curl -s ${API_SERVER_ADDR}/apis/apps/v1/namespaces/default/statefulsets/sts-redis-cluster | jq ".code")
        if [[ $Listener == "404" ]] ; then
            echo_info ">>> Api server addr: ${API_SERVER_ADDR}"
            echo_info ">>> Waiting Until the StatefulSet->sts-redis-cluster is Created... "
            sleep 20
            continue
        else
            break
        fi
    done

    log_info ">>> Performing Cluster Config Check"
    REPLICAS=$(curl -s ${API_SERVER_ADDR}/apis/apps/v1/namespaces/default/statefulsets/sts-redis-cluster | jq ".spec.replicas")

    echo_info "+--------------------------------------------------------------------+"
    echo_info "|                                                                    |"
    echo_info "|\t\tREPLICAS: $REPLICAS"
    echo_info "|                                                                    |"
    echo_info "+--------------------------------------------------------------------+"


    let CLUSER_POD_QUANTUM=REDIS_CLUSTER_SLAVE_QUANTUM*3+3
    if test $REPLICAS -lt $CLUSER_POD_QUANTUM ; then
        log_error " We Need More Pods, please reset the \"replicas\" in  sts-redis-cluster.yaml and recreate the StatefulSet"
        log_error "[IMPORTANT] =>   pod_replicas >= (slave_replicas + 1) * 3"
        exit 1
    else
        log_info "[OK] Cluster Config OK..."
    fi

    log_info ">>> Performing Redis Cluster Pod Check..."

    while true; do
        IP_ARRAY=$(nslookup $CLUSTER_SVC | grep 'Address' |awk '{print $3}')
        log_info "Ready Pod IP : $IP_ARRAY"
        CLUSTER_CONFIG=""
        index=0
        for ip in $IP_ARRAY ;
        do
            redis-cli -h ${ip} -p ${REDIS_PORT} INFO > tempinfo.log
            if test "$?" != "0" ; then
                log_error " Connected to $ip failed ,execute break"
                break
            fi
            CLUSTER_CONFIG=${ip}":${REDIS_PORT} "${CLUSTER_CONFIG}
            log_info "Cluster config : $CLUSTER_CONFIG"
            CLUSTER_NODE=${ip}
            let index++
        done

        log_info "index : $index "
        if test $index -ge $REPLICAS ; then
            log_info ">>> Performing Build Redis Cluster..."
            if test $REDIS_CLUSTER_SLAVE_QUANTUM -eq 0 ;then
                yes yes | head -1 | /code/redis/redis-trib.rb create  $CLUSTER_CONFIG
            else
                yes yes | head -1 | /code/redis/redis-trib.rb create --replicas $REDIS_CLUSTER_SLAVE_QUANTUM $CLUSTER_CONFIG
            fi
            log_info "[OK] Congratulations,Redis Cluster Completed!"
            break
        else
            log_info "Waiting for all pod to be ready! Sleep 5 secs..."
            sleep 5
            continue
        fi
    done

    while true ; do
        log_info ">>> Performing Check Redis Cluster Pod Replicas"
        NEW_REPLICAS=$(curl -s ${API_SERVER_ADDR}/apis/apps/v1/namespaces/default/statefulsets/sts-redis-cluster | jq ".spec.replicas")
        NODES=$(curl -s ${API_SERVER_ADDR}/api/v1/nodes | jq ".items | length")
        HOST_NETWORK=$(curl -s ${API_SERVER_ADDR}/apis/apps/v1/namespaces/default/statefulsets/sts-redis-cluster | jq ".spec.template.spec.hostNetwork" )
        log_info "Current Pod Replicas : $NEW_REPLICAS"
        log_info "Current Nodes Quantum : $NODES"

        if test $NEW_REPLICAS -gt $NODES ; then
            if test $HOST_NETWORK == "true" ; then
                log_warn " When you use host network,make sure that the number of pod is less than node"
                NEW_REPLICAS=$NODES
            fi
        fi

        if test $NEW_REPLICAS -ge $REPLICAS ;then
            if test $NEW_REPLICAS -eq $REPLICAS ;then
                log_info ">>> Performing Check Redis Cluster..."
                /code/redis/redis-trib.rb check $CLUSTER_NODE:$REDIS_PORT
                sleep 120
            else
                log_info ">>> Performing Add Node To The Redis Cluster"
                while true ; do
                    NEW_IP_ARRAY=$(nslookup $CLUSTER_SVC | grep 'Address' |awk '{print $3}')
                    log_info "Ready Pod IP : $NEW_IP_ARRAY"
                    new_index=0
                    for ip in $NEW_IP_ARRAY ;
                    do
                        redis-cli -h ${ip} -p ${REDIS_PORT} INFO > tempinfo.log
                        if test "$?" != "0" ; then
                            log_error " Connected to $ip failed ,execute break"
                            break
                        fi
                        let new_index++
                    done

                    log_info "index : $new_index "

                    if test $new_index -ge $NEW_REPLICAS ; then
                        log_info ">>> Performing Add New Node To The Existed Redis Cluster..."

                        for ip_a in $NEW_IP_ARRAY ; do
                            EXISTS=0
                            for ip_b in $IP_ARRAY ; do
                                if test $ip_a == $ip_b ; then
                                    EXISTS=1
                                    break
                                fi
                            done

                            if  test $EXISTS -eq 0 ; then
                                /code/redis/redis-trib.rb add-node --auto $ip_a:$REDIS_PORT  $CLUSTER_NODE:$REDIS_PORT
                            fi
                        done

                        REPLICAS=$NEW_REPLICAS

                        log_info "[OK] Congratulations,Redis Cluster Completed!"
                        break
                    else
                        log_info "Waiting for all pod to be ready! sleep 5 secs..."
                        sleep 5
                        continue
                    fi
                done
            fi
        else
            log_error "Sorry,We do not support the delete node operation"
        fi
    done
}


if test $# -ne 0 ; then
    case $1 in
        "health")
            /code/redis/redis-trib.rb check --health sts-redis-cluster-0.svc-redis-cluster:$REDIS_PORT
            ;;
        *)
            log_error "wrong arguments!"
        ;;
    esac
    exit 0
fi

time=$(date "+%Y-%m-%d")
echo_info "************************************************************************************"
echo_info "\t\t\t"
echo_info "\t\t\t Redis-in-Kubernetes"
echo_info "\t\t\t Start Date: $time"
echo_info "\t\t\t"
echo_info "************************************************************************************"


if test ! -e /data/redis/master ; then
    mkdir -p /data/redis/master
fi

if test ! -e /data/redis/slave ; then
    mkdir -p /data/redis/slave
fi

if test ! -e /data/redis/cluster ; then
    mkdir -p /data/redis/cluster
fi

if [[ $MASTER == "true" ]] ; then
    master_launcher
    exit 0
fi

if [[ $SLAVE == "true" ]] ; then
    slave_launcher
    exit 0
fi

if [[ $SENTINEL == "true" ]] ; then
    sentinel_launcher
    exit 0
fi

if [[ $CLUSTER == "true" ]] ; then
    cluster_launcher
    exit 0
fi

if [[ $CLUSTER_CTRL == "true" ]] ; then
    cluster_ctrl_launcher
    exit 0
fi
