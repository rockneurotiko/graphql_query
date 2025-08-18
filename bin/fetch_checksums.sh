#!/usr/bin/env bash

rm -rf native/graphql_query_native/target
FORCE_BUILD=true mix rustler_precompiled.download GraphqlQuery.Native --all --print
