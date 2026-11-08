FROM node:24-alpine@sha256:1200d815de24f8dcca745fbf7651d166034a35adbcad8860a8538ffff44f1420 AS build
WORKDIR /app
ARG VITE_R2_MEDIA_UPLOADS=false
ENV VITE_R2_MEDIA_UPLOADS=$VITE_R2_MEDIA_UPLOADS
COPY frontend/package*.json ./
RUN npm ci --ignore-scripts
COPY frontend ./
RUN npm run build

FROM nginx:1.29-alpine3.23-slim@sha256:c9366b8c560169b101ca0e5422ed063b20779e6454c2326b9c9704225c9b0c08
RUN apk upgrade --no-cache
COPY --from=build /app/dist /usr/share/nginx/html
COPY infra/nginx.conf /etc/nginx/conf.d/default.conf
