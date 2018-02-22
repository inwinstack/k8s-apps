#!/bin/bash
#
# Kafka exec script

# Disable Kafka's GC logging (which logs to a file)...
# but enable equivalent GC logging to stdout
export GC_LOG_ENABLED="false"
export JMX_PORT="5555"
export KAFKA_GC_LOG_OPTS="-verbose:gc -XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+PrintGCTimeStamps"
export KAFKA_BROKER_ID=${HOSTNAME##*-}

# volume for saving Kafka server logs
export KAFKA_VOLUME="/var/lib/kafka"
export KAFKA_LOG_DIRS="${KAFKA_DATA_DIR}/log-${KAFKA_BROKER_ID}"

# set log level and opts
if [ -z "${KAFKA_LOG_LEVEL}" ]; then
  KAFKA_LOG_LEVEL="INFO"
fi

if [ -z "$KAFKA_LOG4J_OPTS" ]; then
  export KAFKA_LOG4J_OPTS="-Dlog4j.configuration=file:${KAFKA_HOME}/config/log4j.properties -Dkafka.root.logger.level=${KAFKA_LOG_LEVEL},CONSOLE"
fi

# print infos
echo "+==== start broker ${KAFKA_BROKER_ID} ====+"
echo "Kafka log level: ${KAFKA_LOG_LEVEL}"
echo "Kafka log dir: ${KAFKA_LOG_DIRS}"
echo "Kafka log4j opts: ${KAFKA_LOG4J_OPTS}"

if [ ! -z "${ADVERTISED_ADDRESS}" ]; then
  echo "Kafka advertised address: ${ADVERTISED_ADDRESS}"
  ADVERTISED_OPTS="OUTSIDE://${ADVERTISED_ADDRESS},PLAINTEXT://:9092"
  OPTS="${OPTS} --override advertised.listeners=${ADVERTISED_OPTS}"
fi
echo "+================================+"

# starting Kafka server with final configuration
exec ${KAFKA_HOME}/bin/kafka-server-start.sh ${KAFKA_HOME}/config/server.properties \
  --override broker.id=${KAFKA_BROKER_ID} \
  --override zookeeper.connect=${KAFKA_ZOOKEEPER_CONNECT:-zookeeper:2181} \
  --override log.dirs=${KAFKA_LOG_DIRS} ${OPTS}
