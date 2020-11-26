#!/bin/bash

docker stop journal-db
docker rm journal-db
docker build --tag="localhost:5000/journal-db" -f docker/Dockerfile .
docker push localhost:5000/journal-db
docker run -d -e POSTGRES_PASSWORD=secret -e POSTGRES_DB=documents -p 5432:5432/tcp --name journal-db localhost:5000/journal-db
docker logs -f journal-db
