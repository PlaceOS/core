#! /usr/bin/env bash
# shellcheck disable=2016,2086

set -eu

if [ -z ${GITHUB_ACTION+x} ]
then
  echo '░░░ `crystal tool format --check`'
  crystal tool format --check

  echo '░░░ `ameba`'
  crystal lib/ameba/bin/ameba.cr
fi

watch="false"
coverage="false"
shell="false"
PARAMS=""

while [[ $# -gt 0 ]]
do
  arg="$1"
  case $arg in
    -c|--coverage)
    coverage="true"
    shift
    ;;
    -w|--watch)
    watch="true"
    shift
    ;;
    -s|--shell)
    shell="true"
    shift
    ;;
    *)
    PARAMS="$PARAMS $1"
    shift
    ;;
  esac
done

sed '/ameba/d' shard.yml.input > shard.yml
shards check --ignore-crystal-version -q &> /dev/null || shards install

if [[ "$watch" == "true" ]]; then
  CRYSTAL_WORKERS=1 watchexec -e cr -c -r -w shard.lock -w src -w spec -- scripts/crystal-spec.sh -v $PARAMS
elif [[ "$coverage" == "true" ]]; then
  CRYSTAL_WORKERS=1 crkcov --verbose --output --executable-args "$PARAMS"
elif [[ "$shell" == "true" ]]; then
  /bin/bash
else
  CRYSTAL_WORKERS=1 scripts/crystal-spec.sh -v $PARAMS
fi
