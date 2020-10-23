#! /usr/bin/env bash

set -eu

echo '### Running `crystal tool format --check`'
crystal tool format --check

echo '### Running `ameba`'
crystal lib/ameba/bin/ameba.cr

watch=false
while [[ $# -gt 0 ]]
do
  arg="$1"
  case $arg in
    -w|--watch)
    watch=true
    shift
    ;;
  esac
done

echo '### Running `crystal spec`'

if [[ $watch == "true" ]]; then
  watchexec -e cr -c -r -w src -w spec -- crystal spec --error-trace -v
else
  crystal spec --error-trace -v
fi
