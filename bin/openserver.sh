#!/bin/bash

OPENAPI_BACKEND=PgFarm
OPENAPI_COMMAND=fastcgi
OPENAPI_URL_PREFIX=openapi
OPENAPI_CACHE=mmap
OPENAPI_COLUMN_LIMIT=100
OPENAPI_RECORD_LIMIT=10000

export OPENAPI_BACKEND OPENAPI_COMMAND

BASEDIR=`dirname $0`

OPENAPI="${BASEDIR}/openapi.pl"


case "$1" in
 start)
        echo "OpenAPI server starting..."
        $OPENAPI start &
        disown
        ;;
 stop)
        echo "OpenAPI server stoping..."
        pid=`ps axuww|grep [o]penapi |awk '{print $2}'`
        if [ 'x$pid' != 'x' ]; then
                sudo kill -9 $pid
        else
                echo "no openapi pid found!"
        fi
        ;;
 *)
        echo $"Usage: $0 {start|stop}"
        exit 1
        ;;
esac

