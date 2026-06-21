#!/bin/sh
priv/headless-browser/restart.sh
ERL_FLAGS='+pc unicode' rebar3 shell
