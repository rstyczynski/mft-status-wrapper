#!/bin/bash

function fetchMFTEventStatus() {
    event_session_id=$1

    if [ -z "$event_session_id" ]; then
        echo "Error. Provide event id as first parameter."
        return 1
    fi

    if [ ! -f ~/.mft/mftauth.cfg ]; then
        echo "Error. Provide MFT credentials in ~/.mft/mftauth.cfg file in format user:pass."
        return 1
    fi

    if [ -z "$mftserver" ]; then
        echo "Error. Provide MFT server URL in mftserver variable in format http://ip or https://ip"
        return 1
    fi

    if [ -z "$mftlog" ]; then
        mftlog=.
    fi

    mkdir -p $mftlog/$event_session_id

    timestamp=$(date +%Y%m%dT%H%M%S)

    curl -s -X GET -u $(cat ~/.mft/mftauth.cfg) -H "Content-Type: application/json" $mftserver/mftapp/rest/v1/events/$event_session_id >$mftlog/$event_session_id/$timestamp-raw.json
    if [ $? -ne 0 ]; then
        echo "Error. Not able to connect to MFT instnace."
        return 2
    fi

    cat $mftlog/$event_session_id/$timestamp-raw.json | jq >$mftlog/$event_session_id/$timestamp-event.json

    grep MFT_WS_EVENT_SERVICE_NO_EVENT_FOUND $mftlog/$event_session_id/$timestamp-event.json >/dev/null
    if [ $? -ne 0 ]; then

        curl -s -X GET -u $(cat ~/.mft/mftauth.cfg) -H "Content-Type: application/json" $mftserver/mftapp/rest/v1/events/$event_session_id/instances |
            jq >$mftlog/$event_session_id/$timestamp-instances.json

        curl -s -X GET -u $(cat ~/.mft/mftauth.cfg) -H "Content-Type: application/json" $mftserver/mftapp/rest/v1/events/$event_session_id/instances?inDetail=true |
            jq >$mftlog/$event_session_id/$timestamp-details.json
    else
        echo "Error. Event not found."
        return 3
    fi
}

function getMFTCurrentStatus() {
    event_session_id=$1

    if [ -z "$event_session_id" ]; then
        echo "Error. Provide event id as first parameter."
        return 1
    fi

    if [ -z "$mftlog" ]; then
        mftlog=.
    fi

    current=$(ls -tr $mftlog/$event_session_id/*event* | tail -1)
    #echo
    #echo $current
    cat $current | jq
}

function getMFTActiveStatus() {
    event_session_id=$1

    if [ -z "$event_session_id" ]; then
        echo "Error. Provide event id as first parameter."
        return 1
    fi

    if [ -z "$mftlog" ]; then
        mftlog=.
    fi

    current=$(ls -tr $mftlog/$event_session_id/*details* | tail -1)
    #echo
    #echo $current
    cat "$current" | jq '.instances[] | select(.status.status == "ACTIVE")'
}

function getEventStatus() {
    event_session_id=$1

    if [ -z "$event_session_id" ]; then
        echo "Error. Provide event id as first parameter."
        return 1
    fi

    if [ -z "$mftlog" ]; then
        mftlog=.
    fi

    unset activeInstanceCount
    unset completedInstanceCount
    unset failedInstanceCount
    unset status

    eval $(getMFTCurrentStatus $event_session_id | jq | grep ':' | tr -d '"' | tr -d ' ' | tr -d ',' | tr ':' '=')

    #to test state change
    #activeInstanceCount=0
    #failedInstanceCount=15

    if [ $status == "DONE" ]; then

        if [ $activeInstanceCount -gt 0 ]; then
            echo "{
    \"activeInstanceCount\": \"$activeInstanceCount\",
    \"completedInstanceCount\": \"$completedInstanceCount\",
    \"failedInstanceCount\": \"$failedInstanceCount\",
    \"status\": \"$status\",
    \"effective_status\": \"ALL_IN_PROGRESS\"
}"
        else

            if [ $failedInstanceCount -gt 0 ]; then
                echo "{
    \"activeInstanceCount\": \"$activeInstanceCount\",
    \"completedInstanceCount\": \"$completedInstanceCount\",
    \"failedInstanceCount\": \"$failedInstanceCount\",
    \"status\": \"$status\",
    \"effective_status\": \"FAILED\"
}"
            else
                echo "{
    \"activeInstanceCount\": \"$activeInstanceCount\",
    \"completedInstanceCount\": \"$completedInstanceCount\",
    \"failedInstanceCount\": \"$failedInstanceCount\",
    \"status\": \"$status\",
    \"effective_status\": \"DONE\"
}"
            fi
        fi
    else
        echo "{
    \"activeInstanceCount\": \"$activeInstanceCount\",
    \"completedInstanceCount\": \"$completedInstanceCount\",
    \"failedInstanceCount\": \"$failedInstanceCount\",
    \"status\": \"$status\",
    \"effective_status\": \"$status\"
}"

    fi

}

function getMFTStatusCSV() {
    event_session_id=$1

    if [ -z "$event_session_id" ]; then
        echo "Error. Provide event id as first parameter."
        return 1
    fi

    if [ ! -f $toolsBin/addTimestamp.pl ]; then
        echo "Error. Provide UMC bin in toolsBin."
        return 1
    fi

    if [ -z "$mftlog" ]; then
        mftlog=.
    fi

    short_stat=$(getEventStatus $event_session_id | jq | grep ':' | tr -d '"' | tr -d ' ' | cut -f2 -d: | tr -d '\n')

    current=$(ls -tr $mftlog/$event_session_id/*details* | tail -1)

    cat $current |
        jq -r '.instances[] | [.fileName, .status.status, .status.subStatus, .details.bytesReceived, .details.targets[0].status, .details.targets[0].deliveryStatus, .details.targets[0].bytesTransferred] | @tsv' |
        column -t |
        tr -s ' ' |
        tr ' ' ',' |
        sed "s/^/$short_stat,/g" |
        sed "s/^/$event_session_id,/g" |
        perl $toolsBin/addTimestamp.pl >> $mftlog/$event_session_id/status.log
}

function activeMFTStatus() {
    event_session_id=$1
    if [ -z "$2" ]; then
        verbose=NO
    else
        verbose=YES
    fi

    if [ -z "$event_session_id" ]; then
        echo "Error. Provide event id as first parameter."
        return 1
    fi

    if [ -z "$mftlog" ]; then
        mftlog=.
    fi

    go=1
    while [ $go -eq 1 ]; do
        fetchMFTEventStatus $event_session_id
        if [ $? -ne 0 ]; then
            go=0
        else

            if [ $verbose == YES ]; then
                getMFTCurrentStatus $event_session_id
                getEventStatus $event_session_id
                getMFTActiveStatus $event_session_id
            fi

            getMFTStatusCSV $event_session_id

            getEventStatus $event_session_id | jq -r .effective_status | egrep "DONE|FAILED" >/dev/null
            go=$?
            if [ $go -eq 1 ]; then
                sleep 1
            fi
        fi
    done

}
