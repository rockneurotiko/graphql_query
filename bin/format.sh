#!/usr/bin/env bash

FORCE_BUILD=true mix format

current_dir=$(pwd)

cd ./native/graphql_query_native

cargo fmt

cd "$current_dir"
