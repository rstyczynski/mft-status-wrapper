#!/bin/bash
me=$0
mode=$1

if [ ! ~/.mft/mft.cfg ]; then
  echo "Error. ~/.mft/mft.cfg does not exit. Provide:"
  echo "1) mftserver=http[s]://mft.host.acme.com:port as main mft server address"
  echo "2) mftlog=path as directory for event data"
  echo "3) wrapper_port=8888 to set tcp port for this service to listen on"
  exit 1
fi

if [ ! ~/.mft/mftauth.cfg ]; then
  echo "Error. ~/.mft/mftauth.cfg does not exit. Provide MFT credentials in ~/.mft/mftauth.cfg file in format user:pass."
  exit 1
fi

export binRoot="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

### read cfg
eval $(cat ~/.mft/mft.cfg | grep -v mftauth)

if [ -z "$wrapper_port" ]; then
  wrapper_port=6502
fi

if [ "$mode" != "HANDLER" ]; then
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

# variables: https://stackoverflow.com/questions/3919755/how-to-parse-query-string-from-a-bash-cgi-script
# old style for bash <4
eventId_raw=$(echo "$HTTP_ACTION" | perl -ne '/eventId=([^?& ]*)/ && print $1')
eventId=$(echo -e $(echo "$eventId_raw" | sed 's/+/ /g;s/%\(..\)/\\x\1/g;'))

echo "path:        $urlpath" >&2
echo "eventid:     $eventId" >&2
echo '----' >&2

###
### Main program goes here
###

### load finctions
source $binRoot/status.sh

### set -x to debug
set +x

### route logic
case $urlpath in

/status)
  fetchMFTEventStatus $eventId >&2
  error_code=$?
  if [ $error_code -ne 0 ]; then
    echo HTTP/1.1 404 Not Found
    echo Content-Type\: text/plain
    echo
    echo "Event does not exit or server/network error. Code: $error_code"
    echo "Event does not exit or server/network error. Code: $error_code" >&2
  else
    echo HTTP/1.1 200 OK
    echo Content-Type\: application/json
    echo
    getEventStatus $eventId
    echo OK >&2
  fi
  ;;

/trace)
  if [ -f $mftlog/$eventId/status.log ]; then

    echo HTTP/1.1 200 OK
    echo Content-Type\: text/plain
    echo
    cat $mftlog/$eventId/status.log
    echo OK >&2

  else
    fetchMFTEventStatus $eventId >&2
    error_code=$?
    if [ $error_code -ne 0 ]; then
      echo HTTP/1.1 404 Not Found
      echo Content-Type\: text/plain
      echo
      echo "Event does not exit or server/network error. Code: $error_code"
      echo "Event does not exit or server/network error. Code: $error_code" >&2
    else

      if [ -f /tmp/$eventId.lock ]; then

        echo HTTP/1.1 203 Non-Authoritative Information
        echo Content-Type\: text/csv
        echo
        cat $mftlog/$eventId/status.log
        echo OK >&2

      else

        echo $$ >/tmp/$eventId.lock

        echo HTTP/1.1 201 Created
        echo Content-Type\: text/plain
        echo
        echo Monitoring EventId: $eventId
        echo

        echo "Starting active monitoring of $eventId..."
        echo OK >&2

        (

          ### read cfg
          eval $(cat ~/.mft/mft.cfg | grep -v mftauth)
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
