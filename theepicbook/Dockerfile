# ── Backend Service ──
# Handles Express API routes (/api/*) and Handlebars SSR (/, /cart, /gallery)

# Stage 1: Install production dependencies
FROM node:18-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --production

# Stage 2: Production image
FROM node:18-alpine
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY server.js ./
COPY config/ ./config/
COPY models/ ./models/
COPY routes/ ./routes/
COPY views/ ./views/
COPY public/ ./public/
RUN chown -R appuser:appgroup /app
USER appuser
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://localhost:8080/ || exit 1
CMD ["node", "server.js"]
