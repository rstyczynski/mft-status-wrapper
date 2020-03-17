
# Configure

To prepare functions for work set server, username, and password in cfg file. By default scripts will save data in current dir. You may specify own directory to store data files.

```
mkdir -p ~/.mft
mkdir ~/mft/logs

cat >~/.mft/mft.cfg <<EOF
mftserver=http://mft.acme.com
mftlog=~/mft/logs
EOF

cat >~/.mft/mftauth.cfg <<EOF
mftuser:welcome1
EOF
```

Register function in current shell session.

```
source status.sh
```


# Fetch status from MFT server

This function gets data over HTTP from MFT instance. This call is required for other functions to work with latest data.

```
eventId=1465CAD9-8400-4FC7-9725-E783F03627C4
fetchMFTEventStatus $eventId
```

Event state is written in three files with high, medium, and low level status.

# Display fetched data

Get status with state machine adjusted to real situation. DONE is changed to DOWNLOADED or FAILED depending on values of active and failed counters.


```
eventId=1465CAD9-8400-4FC7-9725-E783F03627C4
getEventStatus $eventId
```

```
{
    "activeInstanceCount": "0",
    "completedInstanceCount": "283",
    "failedInstanceCount": "0",
    "status": "DONE"
}
```

Get files in transit.

```
eventId=1465CAD9-8400-4FC7-9725-E783F03627C4
getMFTActiveStatus $eventId
```

Get complete status in CSV format.

```
eventId=1465CAD9-8400-4FC7-9725-E783F03627C4
getMFTStatusCSV $eventId
```

```
2020-03-15,21:47:53,+0100,1584305273,1465CAD9-8400-4FC7-9725-E783F03627C4,0,283,0,DONE,885_0000636_2020_03_15.csv,COMPLETED,SUCCESSFUL,89221,COMPLETED,SUCCESSFUL,89221
2020-03-15,21:47:53,+0100,1584305273,1465CAD9-8400-4FC7-9725-E783F03627C4,0,283,0,DONE,709_0000636_2020_03_15.csv,COMPLETED,SUCCESSFUL,18202204,COMPLETED,SUCCESSFUL,18202204
2020-03-15,21:47:53,+0100,1584305273,1465CAD9-8400-4FC7-9725-E783F03627C4,0,283,0,DONE,608_0000636_2020_03_15.csv,COMPLETED,SUCCESSFUL,43778934,COMPLETED,SUCCESSFUL,43778934
(...)
```

# Active 

Avtive status works in loop until status of the event is returned as DONE or FAILED. Status is written in status.log csv file with all information from high and low level status data structures. Note that Target details describes only first Target.

```
eventId=1465CAD9-8400-4FC7-9725-E783F03627C4
activeMFTStatus $eventId
```

Saves data in $mftlog/$eventId/status.log file.

```
tail -1 $mftlog/$eventId/status.log

2020-03-15,21:47:53,+0100,1584305273,1465CAD9-8400-4FC7-9725-E783F03627C4,0,283,0,DONE,inv_position_MENA_nf_SAU_HEN_722_0000636_2020_03_15.csv,COMPLETED,SUCCESSFUL,38228526,COMPLETED,SUCCESSFUL,38228526
```


# MFT status (out of the box)

Check status with logical errors as defined by MFT. The problem is that status is returned as DONE even when there are active transport sessions to Target or some instances has failed. Thsi function has no business value, and is added to present current MFT behavior.

```
eventId=1465CAD9-8400-4FC7-9725-E783F03627C4
getMFTCurrentStatus $eventId
```
```
{
  "activeInstanceCount": "0",
  "completedInstanceCount": "283",
  "failedInstanceCount": "0",
  "status": "DONE"
}
```

# MFT status HTTP wrapper

It's possible to interact with scripts over HTTP protocol. Service wrapper offers:

- status check
- trace start
- trace download

To run http sever:

```
bin/mft-status-proxy.sh
```

By default service listens on port 6502, use wrapper_port cfg parameter to set different port.


## get status

```
curl "http://localhost:6502/status?eventId=FE6B5255-8572-4B56-93BE-CEA581F4DCD8"
{
    "activeInstanceCount": "0",
    "completedInstanceCount": "283",
    "failedInstanceCount": "0",
    "status": "DONE",
    "effective_status": "DONE"
}
```

## start trace

To initiate trace invoke trace function with required event id.

```
curl -s "http://localhost:6502/trace?eventId=FE6B5255-8572-4B56-93BE-CEA581F4DCD8"
```

Note that only one collection for event id may be performed at a time. YOu will be notified by error that there is ongoing data collection. Collector will work until transfer reaches DONE or FAILED state.


## get trace result

Once trace is finished trace returns collected data.

```
curl -s "http://localhost:6502/trace?eventId=FE6B5255-8572-4B56-93BE-CEA581F4DCD8" | head -2
2020-03-16,20:02:10,+0100,1584385330,FE6B5255-8572-4B56-93BE-CEA581F4DCD8,0,1,0,IN_PROGRESS,inv_position_MENA_nf_ARE_COL_416_0000638_2020_03_16.csv,COMPLETED,SUCCESSFUL,32234,COMPLETED,SUCCESSFUL,32234
2020-03-16,20:02:12,+0100,1584385332,FE6B5255-8572-4B56-93BE-CEA581F4DCD8,0,1,0,IN_PROGRESS,inv_position_MENA_nf_ARE_COL_416_0000638_2020_03_16.csv,COMPLETED,SUCCESSFUL,32234,COMPLETED,SUCCESSFUL,32234
```




