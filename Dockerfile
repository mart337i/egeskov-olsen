# syntax=docker/dockerfile:1
ARG NODE_VERSION=18.19.1
ARG PNPM_VERSION=9.14.4

################################################################################
# Use node image for base image for all stages.
FROM node:${NODE_VERSION}-slim as base

# Install Sharp dependencies for Debian
RUN apt-get update && apt-get install -y \
    libvips-dev \
    python3 \
    make \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Set working directory for all build stages.
WORKDIR /usr/src/app

# Install pnpm.
RUN --mount=type=cache,target=/root/.npm \
    npm install -g pnpm@${PNPM_VERSION}

################################################################################
# Create a stage for installing production dependencies.
FROM base as deps

# Copy package files and pnpm config
COPY package.json pnpm-lock.yaml .npmrc ./

# Install production dependencies
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    pnpm install --prod --frozen-lockfile

################################################################################
# Create a stage for building the application.
FROM base as build

# Copy package files and pnpm config
COPY package.json pnpm-lock.yaml .npmrc ./

# Install all dependencies including dev dependencies
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    pnpm install --frozen-lockfile

# Explicitly install and rebuild Sharp for pnpm compatibility
RUN pnpm add sharp && pnpm rebuild sharp

# Copy the rest of the source files into the image.
COPY . .

# Run the build script.
RUN pnpm run build

################################################################################
# Create a new stage to run the application with minimal runtime dependencies
FROM base as final

# Use production node environment by default.
ENV NODE_ENV production

# Run the application as a non-root user.
ARG UID=10001
RUN adduser \
    --disabled-password \
    --gecos "" \
    --home "/nonexistent" \
    --shell "/sbin/nologin" \
    --no-create-home \
    --uid "${UID}" \
    appuser
USER appuser

# Copy package.json so that package manager commands can be used.
COPY package.json .

# Copy the production dependencies from the deps stage and also
# the built application from the build stage into the image.
COPY --from=deps /usr/src/app/node_modules ./node_modules
COPY --from=build /usr/src/app/dist ./dist
COPY --from=build /usr/src/app/package.json ./package.json

# Expose the port that the application listens on.
EXPOSE 4321

# Run the application.
CMD pnpm start --host