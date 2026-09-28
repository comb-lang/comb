#!/usr/bin/env sh
set -e
rm -rf build
docker build -t comb .
trap "docker rm -f comb" EXIT
docker create --name comb comb
rm -rf gitignore_docker_build
docker cp comb:/build gitignore_docker_build
