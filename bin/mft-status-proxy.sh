#!/bin/bash
me=$0
mode=$1
case $mode in
WRAPPER | HANDLER) ;;
  # OK

*)
  echo >&2 'Error...\n'
  exit 1
  ;;
esac

mft_env=$2
if [ -z "$mft_env" ]; then
  mft_env=mft
fi

if [ ! ~/.mft/$mft_env.cfg ]; then
  echo "Error. ~/.mft/$mft_env.cfgdoes not exit. Provide:"
  echo "1) mftserver=http[s]://mft.host.acme.com:port as main mft server address"
  echo "2) mftlog=path as directory for event data"
  echo "3) wrapper_port=8888 to set tcp port for this service to listen on"
  exit 1
fi

if [ ! ~/.mft/$mft_env.auth ]; then
  echo "Error. ~/.mft/$mft_env.auth does not exit. Provide MFT credentials in ~/.mft/$mft_env.auth file in format user:pass."
  exit 1
fi

export binRoot="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "$wrapper_port" ]; then
  wrapper_port=6502
fi

if [ "$mode" == "WRAPPER" ]; then
  echo "Starting service listener..."
  socat TCP-LISTEN:$wrapper_port,crlf,reuseaddr,fork EXEC:"$me HANDLER"
  # to debug add: -v -d -d
  exit 0
fi

###
### HTTP handler program goes here. Below code is executed in fork mode.
###

###
### Session parameters are logged
###

echo '----' >&2
set | grep SOCAT >&2
echo '----' >&2

read -r HTTP_ACTION

echo '----' >&2
echo "HTTP action: $HTTP_ACTION" >&2

# GET /abcs/?eventId=FE6B5255-8572-4B56-93BE-CEA581F4DCD1&var2=abc2312312 HTTP/1.1
urlpath=$(echo "$HTTP_ACTION" | perl -ne '/GET ([^?]*)(.*) HTTP/ && print $1')

mft_env=$(echo $urlpath | cut -f2 -d'/')
mft_action=$(echo $urlpath | cut -f3 -d'/')

# variables: https://stackoverflow.com/questions/3919755/how-to-parse-query-string-from-a-bash-cgi-script
# old style for bash <4
eventId_raw=$(echo "$HTTP_ACTION" | perl -ne '/eventId=([^?& ]*)/ && print $1')
eventId=$(echo -e $(echo "$eventId_raw" | sed 's/+/ /g;s/%\(..\)/\\x\1/g;'))

echo "path:        $urlpath" >&2
echo "mft_env:     $mft_env" >&2
echo "mft_action:  $mft_action" >&2
echo "eventid:     $eventId" >&2
echo '----' >&2

###
### Main program goes here
###

### read cfg
eval $(cat ~/.mft/$mft_env.cfg | grep -v mftauth)

### load functions
source $binRoot/status.sh

### set -x to debug
set +x

### check state
fetchMFTEventStatus $eventId >&2
error_code=$?
if [ $error_code -ne 0 ]; then
  echo HTTP/1.1 404 Not Found
  echo Content-Type\: text/plain
  echo
  echo "Event does not exists or server/network error. Code: $error_code"
  echo "Event does not exists or server/network error. Code: $error_code" >&2
  exit 1
fi

event_status=$(getEventStatus $event_session_id | jq -r .effective_status)

### route logic
case $mft_action in

status)
  echo HTTP/1.1 200 OK
  echo Content-Type\: application/json
  echo
  getEventStatus $eventId
  echo OK >&2
  ;;

trace)
  if [[ -f $mftlog/$eventId/status.log  && "$event_status" != "ERRORED" ]] ; then
    echo HTTP/1.1 200 OK
    echo Content-Type\: text/plain
    echo
    cat $mftlog/$eventId/status.log
    echo OK >&2
  else
    if [ -f /tmp/$eventId.lock ]; then

      echo HTTP/1.1 203 Non-Authoritative Information
      echo Content-Type\: text/csv
      echo
      cat $mftlog/$eventId/status.log
      echo OK >&2

      #
      # TODO: corner case: check if lock's owner is still working, if not delete lock
      #

    else
      echo $$ >/tmp/$eventId.lock

      echo HTTP/1.1 201 Created
      echo Content-Type\: text/plain
      echo
      echo Monitoring EventId: $eventId
      echo

      echo "Starting active monitoring of $eventId..."
      echo OK >&2

      export mft_env
      (

        if [ -z "$mft_env" ]; then
          mft_env=mft
        fi

        ### read cfg
        eval $(cat ~/.mft/$mft_env.cfg | grep -v mftauth)
        ### load finctions
        source $binRoot/status.sh

        function cleanup() {
          echo cleaning up >&2
          rm -f /tmp/$eventId.lock
        }
        trap cleanup EXIT

        activeMFTStatus $eventId
        sleep 10
        activeMFTStatus $eventId

        cleanup
      ) &
    fi
  fi
  ;;
*)
  echo HTTP/1.1 404 Not Found
  echo Content-Type\: text/plain
  echo
  echo "Unknown service call."

  echo "Unknown service call." >&2
  ;;
esac

### disable debug
set +x
