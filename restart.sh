#!/bin/bash

docker stop journal-db
docker rm journal-db
docker build --tag="localhost:5000/journal-db" -f docker/Dockerfile .
docker push localhost:5000/journal-db
docker run -d -e POSTGRES_PASSWORD=secret -e POSTGRES_DB=documents -p 5432:5432/tcp --name journal-db localhost:5000/journal-db
if [ "$1" = "pro" ]; then # pro for provision ;-)
  sleep 5
  cat > init.sql <<EOF
select * from main.create_document_with_id('12984937-da9d-4d32-8c03-09366b13cf1f', 'night ragas', 'listening to indian music', 'milind chittal', '', 'raga jog', '{"indian", "raga"}', 'werewolf', 'john', 'john@pic.com', 'nottingham', 'doc', 'howto');
select * from main.create_document_with_id('a96ddef3-f7e4-4b46-a7b5-ecfbec10df0e', 'les velos parisiens', 'facture reparation freins', 'sebastien', '', 'durite, tringle, et plaquettes', '{"velo"}', 'velo', 'john', 'john@pic.com', 'nottingham', 'doc', 'howto');
EOF
  psql postgres://postgres:secret@localhost:5432/documents < init.sql
  rm init.sql
else
  docker logs -f journal-db
fi
