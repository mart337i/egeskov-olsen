FROM node:18-alpine

RUN npm install -g pnpm

WORKDIR /app

COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile

COPY . .
RUN pnpm run build

EXPOSE 8888

CMD ["pnpm", "run", "preview", "--host", "0.0.0.0", "--port", "8888"]