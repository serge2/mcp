#!/bin/sh
docker rm -f pw-service ; docker run -d --name pw-service -p 8000:8000 playwright-service