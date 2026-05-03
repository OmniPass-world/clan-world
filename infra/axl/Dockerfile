# syntax=docker/dockerfile:1
# Build AXL node from source (https://github.com/gensyn-ai/axl)
FROM golang:1.25-alpine AS builder
RUN apk add --no-cache git
RUN git clone https://github.com/gensyn-ai/axl /axl && \
    cd /axl && git checkout 9cba555ff0b8e14ebf1244ae02b274fbc4ec044e
WORKDIR /axl
RUN go build -o node ./cmd/node/

FROM alpine:latest
RUN apk add --no-cache openssl ca-certificates wget
WORKDIR /app
COPY --from=builder /axl/node .
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh
EXPOSE 9002
ENTRYPOINT ["./entrypoint.sh"]
