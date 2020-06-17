#!/bin/bash
mft_tracer=$1
logfile=$2
while IFS= read -r event_id; do
  echo $event_id
  curl -s "http://$mft_tracer/mft/trace?eventId=$event_id"
done <<<$(tail -F $logfile | grep -Po '(?<=jca.jms.JMSProperty.EventSessionID=)[\w-]+')


