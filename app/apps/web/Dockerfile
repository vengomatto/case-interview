FROM node:lts-slim AS build

WORKDIR /app

COPY package.json ./
COPY package-lock.json ./
COPY apps/web/package.json ./apps/web/package.json

RUN npm ci

COPY . .


WORKDIR /app/apps/web

# Relative by default: the browser calls /api on the host that served the page.
# docker-compose overrides this with an absolute URL (no ingress there).
ARG VITE_API_BASE=/api
ENV VITE_API_BASE=$VITE_API_BASE
RUN npm run build

CMD ["npx", "vite", "preview"]
