#!/usr/bin/env bash
#
DEFAULT_HTTP_PORT=8080
DEFAULT_TIMEOUT_SECS=60
ALPHAS=()

# ensure each argument is <host>:<port>
for SERVICE in $*; do
    HOST=${SERVICE%:*} PORT=${SERVICE#*:}
    if [[ $HOST == $PORT ]]; then
        ALPHAS+=( $HOST:$DEFAULT_HTTP_PORT )
    elif [[ -z $HOST ]]; then
        ALPHAS+=( localhost:$PORT )
    fi
done

echo -n "Waiting for alphas .."
START_TIME=$(date +%s)
while [[ ${#ALPHAS[*]} -gt 0 ]]; do
    CHECK_AGAIN=()

    for SERVICE in ${ALPHAS[*]}; do
        RESULT=$(curl --silent http://$SERVICE/health)
        if [[ $RESULT != "OK" ]]; then
            CHECK_AGAIN+=( $SERVICE )
        fi
    done

    echo -n "."
    if [[ -z $CHECK_AGAIN ]]; then
        echo
        exit 0
    elif [[ $(( $(date +%s) - $START_TIME )) -ge $DEFAULT_TIMEOUT_SECS ]]; then
        echo
        exit 1
    fi

    ALPHAS=( ${CHECK_AGAIN[*]} )
    sleep 0.5
done
