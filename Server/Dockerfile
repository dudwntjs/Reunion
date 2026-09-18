FROM node:22-alpine
WORKDIR /app
COPY server.mjs package.json ./
ENV PORT=8787
EXPOSE 8787
USER node
CMD ["node", "server.mjs"]
