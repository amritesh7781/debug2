# Stage 1: Build React Frontend
FROM node:20-alpine AS frontend-builder
WORKDIR /app/client
COPY client/package*.json ./
RUN npm install
COPY client/ ./
RUN npm run build

# Stage 2: Install Backend Dependencies
FROM node:20-alpine AS backend-builder
WORKDIR /app/server
COPY server/package*.json ./
RUN npm install --production

# Stage 3: Final Image
FROM node:20-alpine
WORKDIR /app

# Copy built frontend to server/public
COPY --from=frontend-builder /app/client/dist /app/server/public

# Copy backend dependencies and source
COPY --from=backend-builder /app/server/node_modules /app/server/node_modules
COPY server/ /app/server/

# Set Environment Variables
ENV NODE_ENV=production
ENV PORT=5001

# Expose port
EXPOSE 5001

# Start the server
WORKDIR /app/server
CMD ["npm", "start"]
