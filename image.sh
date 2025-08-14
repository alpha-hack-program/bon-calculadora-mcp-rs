#!/bin/bash

# Container management script for weather-mcp
set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment variables
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
    # shellcheck source=.env
    source "${SCRIPT_DIR}/.env"
else
    echo "❌ .env file not found!"
    echo "💡 You can create a .env file with the required variables taking .env.sample as a starting point."
    exit 1
fi

# Default values and computed variables
APP_NAME="${APP_NAME:-test-mcp}"
MAINTAINER="${MAINTAINER-test@acme.com}"
DESCRIPTION="${DESCRIPTION-"Test MCP Server"}"
VERSION="${VERSION:-$(git rev-parse --short HEAD 2>/dev/null || echo 'latest')}"
IMAGE_TAG="${REGISTRY}/${APP_NAME}:${VERSION}"
LATEST_TAG="${REGISTRY}/${APP_NAME}:latest"
CONTAINERFILE="${CONTAINERFILE:-Containerfile}"
SOURCE="${SOURCE:-https://github.com/acme/test-mcp.git}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if required tools are installed
check_dependencies() {
    local missing_deps=()
    
    if ! command -v podman &> /dev/null && ! command -v docker &> /dev/null; then
        missing_deps+=("podman or docker")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        exit 1
    fi
    
    # Determine container runtime
    if command -v podman &> /dev/null; then
        CONTAINER_RUNTIME="podman"
    else
        CONTAINER_RUNTIME="docker"
    fi
}

# Get container runtime
get_runtime() {
    echo "${CONTAINER_RUNTIME}"
}

# Build the container image
build() {
    log_info "Building container image..."
    log_info "Image: ${IMAGE_TAG}"
    log_info "Base: ${BASE_IMAGE}:${BASE_TAG}"
    log_info "Runtime: $(get_runtime)"
    
    # Get build metadata
    local build_date
    build_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local vcs_ref
    vcs_ref=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    
    # Build arguments
    local build_args=(
        "--file" "${CONTAINERFILE}"
        "--tag" "${IMAGE_TAG}"
        "--tag" "${LATEST_TAG}"
        "--build-arg" "BASE_IMAGE=${BASE_IMAGE}"
        "--build-arg" "BASE_TAG=${BASE_TAG}"
        "--build-arg" "VERSION=${VERSION}"
        "--build-arg" "BUILD_DATE=${build_date}"
        "--build-arg" "VCS_REF=${vcs_ref}"
        "--build-arg" "MAINTAINER=${MAINTAINER}"
        "--build-arg" "DESCRIPTION=${DESCRIPTION}"
        "--build-arg" "APP_NAME=${APP_NAME}"
        "--build-arg" "PORT=${PORT}"
        "--build-arg" "SOURCE=${SOURCE}"
    )
    
    # Add cache flag if specified
    if [[ -n "${CACHE_FLAG}" ]]; then
        build_args+=("${CACHE_FLAG}")
    fi
    
    # Add context (current directory)
    build_args+=(".")
    
    log_info "Build arguments:"
    log_info "  BASE_IMAGE=${BASE_IMAGE}"
    log_info "  BASE_TAG=${BASE_TAG}"
    log_info "  VERSION=${VERSION}"
    log_info "  BUILD_DATE=${build_date}"
    log_info "  VCS_REF=${vcs_ref:0:8}"
    log_info "  MAINTAINER=${MAINTAINER}"
    log_info "  DESCRIPTION=${DESCRIPTION}"
    log_info "  APP_NAME=${APP_NAME}"
    log_info "  PORT=${PORT}"
    log_info "  SOURCE=${SOURCE}"
    
    if "$(get_runtime)" build "${build_args[@]}"; then
        log_success "Build completed successfully"
        log_info "Tagged as: ${IMAGE_TAG}"
        log_info "Tagged as: ${LATEST_TAG}"
        
        # Show image information
        log_info "Image details:"
        "$(get_runtime)" inspect "${IMAGE_TAG}" --format '{{.Config.Labels}}' | tr ',' '\n' | grep -E "(version|created|revision)" || true
    else
        log_error "Build failed"
        exit 1
    fi
}

# Push the container image
push() {
    log_info "Pushing container image..."
    
    # Check if we're logged in to the registry
    if ! "$(get_runtime)" info | grep -q "${REGISTRY%%/*}"; then
        log_warning "You may need to login to ${REGISTRY%%/*}"
        log_info "Run: $(get_runtime) login ${REGISTRY%%/*}"
    fi
    
    # Push both tags
    log_info "Pushing ${IMAGE_TAG}..."
    if "$(get_runtime)" push "${IMAGE_TAG}"; then
        log_success "Pushed ${IMAGE_TAG}"
    else
        log_error "Failed to push ${IMAGE_TAG}"
        exit 1
    fi
    
    log_info "Pushing ${LATEST_TAG}..."
    if "$(get_runtime)" push "${LATEST_TAG}"; then
        log_success "Pushed ${LATEST_TAG}"
    else
        log_error "Failed to push ${LATEST_TAG}"
        exit 1
    fi
    
    log_success "Push completed successfully"
}

# Run the container locally
run() {
    log_info "Running container locally..."
    log_info "Image: ${IMAGE_TAG}"
    
    local container_name="${APP_NAME}-local"
    
    # Stop and remove existing container if it exists
    if "$(get_runtime)" ps -a --format "{{.Names}}" | grep -q "^${container_name}$"; then
        log_info "Stopping existing container..."
        "$(get_runtime)" stop "${container_name}" || true
        "$(get_runtime)" rm "${container_name}" || true
    fi
    
    # Run the container
    log_info "Starting new container..."
    "$(get_runtime)" run \
        --name "${container_name}" \
        --rm \
        --interactive \
        --tty \
        --env BIND_ADDRESS=0.0.0.0:${PORT} \
        --publish ${PORT}:${PORT} \
        "${IMAGE_TAG}"
}

# Run the container from remote registry
run_remote() {
    log_info "Running container from remote registry..."
    log_info "Image: ${IMAGE_TAG}"
    
    local container_name="${APP_NAME}-remote"
    
    # Stop and remove existing container if it exists
    if "$(get_runtime)" ps -a --format "{{.Names}}" | grep -q "^${container_name}$"; then
        log_info "Stopping existing container..."
        "$(get_runtime)" stop "${container_name}" || true
        "$(get_runtime)" rm "${container_name}" || true
    fi
    
    # Pull the latest image
    log_info "Pulling latest image..."
    if "$(get_runtime)" pull "${IMAGE_TAG}"; then
        log_success "Pulled ${IMAGE_TAG}"
    else
        log_error "Failed to pull ${IMAGE_TAG}"
        exit 1
    fi
    
    # Run the container
    log_info "Starting new container from remote image..."
    "$(get_runtime)" run \
        --name "${container_name}" \
        --rm \
        --interactive \
        --tty \
        --env BIND_ADDRESS=0.0.0.0:${PORT} \
        --publish ${PORT}:${PORT} \
        "${IMAGE_TAG}"
}

# Test the container (basic health check)
test() {
    log_info "Testing container..."
    
    local test_container="${APP_NAME}-test"
    
    # Run a quick test
    if "$(get_runtime)" run \
        --name "${test_container}" \
        --rm \
        --env NODE_ENV=production \
        "${IMAGE_TAG}" \
        node --version; then
        log_success "Container test passed"
    else
        log_error "Container test failed"
        exit 1
    fi
}

# Clean up images and containers
clean() {
    log_info "Cleaning up..."
    
    # Remove containers
    local containers
    containers=$("$(get_runtime)" ps -a --filter "name=${APP_NAME}" --format "{{.Names}}" || true)
    if [[ -n "${containers}" ]]; then
        log_info "Removing containers: ${containers}"
        echo "${containers}" | xargs "$(get_runtime)" rm -f || true
    fi
    
    # Remove images
    local images
    images=$("$(get_runtime)" images --filter "reference=${REGISTRY}/${APP_NAME}" --format "{{.Repository}}:{{.Tag}}" || true)
    if [[ -n "${images}" ]]; then
        log_info "Removing images: ${images}"
        echo "${images}" | xargs "$(get_runtime)" rmi -f || true
    fi
    
    log_success "Cleanup completed"
}

# Show image information
info() {
    log_info "Container Information"
    echo "App Name: ${APP_NAME}"
    echo "Version: ${VERSION}"
    echo "Image Tag: ${IMAGE_TAG}"
    echo "Latest Tag: ${LATEST_TAG}"
    echo "Registry: ${REGISTRY}"
    echo "Base Image: ${BASE_IMAGE}"
    echo "Container Runtime: $(get_runtime)"
    echo "Containerfile: ${CONTAINERFILE}"
    
    echo ""
    log_info "Available Images:"
    "$(get_runtime)" images --filter "reference=${REGISTRY}/${APP_NAME}" || true
    
    echo ""
    log_info "Running Containers:"
    "$(get_runtime)" ps --filter "name=${APP_NAME}" || true
}

# Show usage information
usage() {
    echo "Usage: $0 {build|push|run|run-remote|test|clean|info}"
    echo ""
    echo "Commands:"
    echo "  build      - Build the container image"
    echo "  push       - Push the container image to registry"
    echo "  run        - Run the container locally"
    echo "  run-remote - Pull and run the container from registry"
    echo "  test       - Test the container"
    echo "  clean      - Clean up containers and images"
    echo "  info       - Show container information"
    echo ""
    echo "Environment variables (from .env):"
    echo "  APP_NAME=${APP_NAME:-weather-mcp}"
    echo "  VERSION=${VERSION}"
    echo "  REGISTRY=${REGISTRY}"
    echo "  BASE_IMAGE=${BASE_IMAGE}"
    echo ""
    echo "Examples:"
    echo "  $0 build"
    echo "  $0 push"
    echo "  $0 run"
    echo "  VERSION=v1.2.3 $0 build"
}

# Main script logic
main() {
    # Check dependencies
    check_dependencies
    
    # Handle commands
    case "${1:-}" in
        build)
            build
            ;;
        push)
            push
            ;;
        run)
            run
            ;;
        run-remote)
            run_remote
            ;;
        test)
            test
            ;;
        clean)
            clean
            ;;
        info)
            info
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            log_error "Unknown command: ${1:-}"
            echo ""
            usage
            exit 1
            ;;
    esac
}

# Execute main function with all arguments
main "$@"