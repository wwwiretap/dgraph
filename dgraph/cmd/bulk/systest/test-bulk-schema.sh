#!/bin/bash
# verify fix of https://github.com/dgraph-io/dgraph/issues/2616
# uses configuration in dgraph/docker-compose.yml

readonly ME=${0##*/}
readonly SRCROOT=$(readlink -f ${BASH_SOURCE[0]%/*}/../../../..)
readonly DOCKER_CONF=$SRCROOT/dgraph/docker-compose.yml
readonly WAIT_FOR_IT=$SRCROOT/contrib/wait-for-it.sh

declare -ri ZERO_PORT=5080 HTTP_PORT=8180

INFO()  { echo "$ME: $@";     }
ERROR() { echo >&2 "$ME: $@"; }
FATAL() { ERROR "$@"; exit 1; }

set -e

INFO "running bulk load schema test"

WORKDIR=$(mktemp --tmpdir -d $ME.tmp-XXXXXX)
INFO "using workdir $WORKDIR"
cd $WORKDIR

trap ErrorExit EXIT

function ErrorExit
{
    local ev=$?
    if [[ ! $DEBUG ]]; then
        rm -rf $WORKDIR
    fi
    if [[ $ev -ne 0 ]]; then
        FATAL "*** unexpected error ***"
    fi
}

function StartZero
{
  INFO "starting zero container"
  docker-compose -f $DOCKER_CONF up --force-recreate --detach zero1
  TIMEOUT=10
  while [[ $TIMEOUT > 0 ]]; do
    if docker logs bank-dg0.1 2>&1 | grep -q 'CID set'; then
      return
    else
      TIMEOUT=$((TIMEOUT - 1))
      sleep 1
    fi
  done
  FATAL "failed to start zero"
}

function StartAlpha
{
  local p_dir=$1

  INFO "starting alpha container"
  docker-compose -f $DOCKER_CONF up --force-recreate --no-start dg1
  if [[ $p_dir ]]; then
    docker cp $p_dir bank-dg1:/data/dg1/
  fi
  docker-compose -f $DOCKER_CONF up --detach dg1

  TIMEOUT=10
  while [[ $TIMEOUT > 0 ]]; do
    if docker logs bank-dg1 2>&1 | grep -q 'Got Zero leader'; then
      return
    else
      TIMEOUT=$((TIMEOUT - 1))
      sleep 1
    fi
  done
  FATAL "failed to start alpha"
}

function ResetCluster
{
    INFO "restarting cluster with only one zero and alpha"
    docker-compose -f $DOCKER_CONF down
    StartZero
    StartAlpha
}

function UpdateDatabase
{
  INFO "adding predicate with default type to schema"
  curl localhost:$HTTP_PORT/alter -X POST -d$'
predicate_with_no_uid_count:string  .
predicate_with_default_type:default  .
predicate_with_index_no_uid_count:string @index(exact) .
' &>/dev/null

  curl localhost:$HTTP_PORT/mutate -X POST -H 'X-Dgraph-CommitNow: true' -d $'
{
  set {
    _:company1 <predicate_with_default_type> "CompanyABC" .
  }
}
' &>/dev/null
}

function QuerySchema
{
  INFO "running schema query"
  local out_file="schema.out"
  curl -sS localhost:$HTTP_PORT/query -XPOST -d'schema(pred:[genre,language,name,revenue,predicate_with_default_type,predicate_with_index_no_uid_count,predicate_with_no_uid_count]) {}' | python -c "import json,sys; d=json.load(sys.stdin); json.dump(d['data'],sys.stdout,sort_keys=True,indent=2)"  > $out_file
  echo >> $out_file
}

function DoExport
{
  INFO "running export"
  docker exec -it bank-dg1 curl localhost:$HTTP_PORT/admin/export &>/dev/null
  sleep 2
  docker cp bank-dg1:/data/dg1/export .
  sleep 1
}

function BulkLoadExportedData
{
  INFO "bulk loading exported data"
  dgraph bulk -z localhost:$ZERO_PORT \
              -s ../dir1/export/*/g01.schema.gz \
              -f ../dir1/export/*/g01.rdf.gz \
     >bulk.log 2>&1 </dev/null
}

function BulkLoadFixtureData
{
  INFO "bulk loading fixture data"

  # schema test cases:
  #
  # 1. predicate with non-default type (name)
  # 2. predicate with default type (genre)
  # 3. predicate not used in rdf (language)
  cat >fixture.schema <<EOF
name:string @index(term) .
genre:default .
language:string .
EOF

  # rdf test cases:
  #
  # 4. predicate not in schema (revenue)
  cat >fixture.rdf <<EOF
_:et <name> "E.T. the Extra-Terrestrial" .
_:et <genre> "Science Fiction" .
_:et <revenue> "792.9" .
EOF

  dgraph bulk -z localhost:$ZERO_PORT -s fixture.schema -f fixture.rdf \
     >bulk.log 2>&1 </dev/null
}

function StopServers
{
  INFO "stoping containers"
  docker-compose -f $DOCKER_CONF down
}

function Cleanup
{
  INFO "removing $WORKDIR"
  rm -rf $WORKDIR
}

mkdir dir1
pushd dir1 >/dev/null

ResetCluster
UpdateDatabase
QuerySchema
DoExport
StopServers

popd >/dev/null
mkdir dir2
pushd dir2 >/dev/null

StartZero
BulkLoadExportedData
StartAlpha "./out/0/p"
QuerySchema
StopServers

popd >/dev/null

INFO "verifing schema is same before export and after bulk import"
diff -b dir1/schema.out dir2/schema.out || FATAL "schema incorrect"
INFO "schema is correct"

mkdir dir3
pushd dir3 >/dev/null

StartZero
BulkLoadFixtureData
StartAlpha "./out/0/p"
QuerySchema
StopServers

popd >/dev/null

# final schema should include *all* predicates regardless of whether they were
# introduced by the schema or rdf file, used or not used, or of default type
# or non-default type
INFO "verifying schema contains all predicates"
diff -b - dir3/schema.out <<EOF || FATAL "schema incorrect"
{
  "schema": [
    {
      "predicate": "genre",
      "type": "default"
    },
    {
      "predicate": "language",
      "type": "string"
    },
    {
      "index": true,
      "predicate": "name",
      "tokenizer": [
        "term"
      ],
      "type": "string"
    },
    {
      "predicate": "revenue",
      "type": "default"
    }
  ]
}
EOF

INFO "schema is correct"

Cleanup

exit 0

# eof
