# syntax=docker/dockerfile:1

# Build arguments
ARG BASE_IMAGE=registry.access.redhat.com/ubi9/ubi-minimal
ARG BASE_TAG=9.6
ARG VERSION=1.0.2
ARG MAINTAINER="Alpha Hack Group <alpha@github.com>"
ARG DESCRIPTION="BON Calculadora MCP Server - Model Context Protocol server para calculadora de BON"
ARG APP_NAME=bon-calculadora-mcp-server
ARG PORT=8001
ARG SOURCE=https://github.com/alpha-hack-program/bon-calculadora-mcp-rs.git

# Multi-stage build
# Stage 1: Build stage with Rust toolchain
FROM registry.access.redhat.com/ubi9/ubi:${BASE_TAG} AS builder

# Install Rust and build dependencies
RUN dnf update -y && \
    dnf install -y \
        gcc \
        gcc-c++ \
        make \
        openssl-devel \
        pkg-config && \
    dnf clean all && \
    rm -rf /var/cache/dnf

# Install Rust
ENV RUSTUP_HOME=/opt/rust
ENV CARGO_HOME=/opt/rust
ENV PATH=/opt/rust/bin:$PATH
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --no-modify-path

# Set working directory
WORKDIR /build

# Copy Cargo TOML
COPY Cargo.* .

# Fetch dependencies
RUN cargo fetch

# Copy the source code
COPY src/ ./src

# Build the application
RUN cargo build --release --bin sse_server

# Stage 2: Runtime stage with minimal UBI
FROM ${BASE_IMAGE}:${BASE_TAG}

# Build arguments for labels
ARG VERSION
ARG BUILD_DATE
ARG VCS_REF
ARG MAINTAINER
ARG DESCRIPTION
ARG APP_NAME
ARG PORT
ARG SOURCE

# Add labels (OCI standard)
LABEL org.opencontainers.image.title="${APP_NAME}" \
      org.opencontainers.image.description="${DESCRIPTION}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.source="${SOURCE}" \
      org.opencontainers.image.authors="${MAINTAINER}" \
      org.opencontainers.image.vendor="Alpha Hack Group" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.url="${SOURCE}" \
      org.opencontainers.image.documentation="${SOURCE}" \
      io.k8s.description="${DESCRIPTION}" \
      io.k8s.display-name="${APP_NAME}" \
      io.openshift.tags="mcp,calculator,rust,server" \
      maintainer="${MAINTAINER}"

# Install runtime dependencies
RUN microdnf update -y && \
    microdnf install -y \
        ca-certificates \
        openssl && \
    microdnf clean all && \
    rm -rf /var/cache/yum

# Create non-root user for security
RUN useradd -r -u 1001 -g 0 -s /sbin/nologin \
    -c "BON Calculadora MCP Server user" mcpserver

# Set working directory
WORKDIR /app

# Copy the binary from builder stage
COPY --from=builder /build/target/release/sse_server /app/sse_server

# Copy data files (if any)
COPY --from=builder /build/src/common/ayuda-excedencia-2025.json /app/ayuda-excedencia-2025.json

# Set permissions
RUN chown -R 1001:0 /app && \
    chmod -R g=u /app && \
    chmod +x /app/sse_server

# Switch to non-root user
USER 1001

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:${PORT}/health || exit 1

# Expose port
EXPOSE ${PORT}

# Environment variables
ENV RUST_LOG=info
ENV RUST_BACKTRACE=1
ENV PORT=${PORT}

# Run the application
CMD ["/app/sse_server"]