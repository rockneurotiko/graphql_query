#!/usr/bin/env bash

rm -rf native/graphql_query_native/target
mix rustler_precompiled.download GraphqlQuery.Native --all --print
