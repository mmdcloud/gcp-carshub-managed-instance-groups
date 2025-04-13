#!/bin/bash
mkdir backend-code
cp -r ../backend/api/* backend-code/
cd backend-code

docker buildx build --tag carshub-backend --file ./Dockerfile .
docker tag carshub-backend:latest us-central1-docker.pkg.dev/orbital-bee-455915-h5/carshub-backend/carshub-backend:latest
docker push us-central1-docker.pkg.dev/orbital-bee-455915-h5/carshub-backend/carshub-backend:latest