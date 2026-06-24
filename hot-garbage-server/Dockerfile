FROM node:18-alpine
WORKDIR /app
COPY hot-garbage-server/package*.json ./hot-garbage-server/
COPY server/ ./server/
COPY data/ ./data/
WORKDIR /app/hot-garbage-server
RUN npm ci --omit=dev
COPY hot-garbage-server/ .
EXPOSE 3000
CMD ["node", "server.js"]
