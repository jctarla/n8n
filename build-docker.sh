#!/bin/bash
set -e

# n8n Docker Build Script
# This script builds the n8n Docker image using the existing build system

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DEFAULT_IMAGE_NAME="n8nio/n8n"
DEFAULT_TAG="local"
IMAGE_NAME="${IMAGE_BASE_NAME:-$DEFAULT_IMAGE_NAME}"
TAG="${IMAGE_TAG:-$DEFAULT_TAG}"
FULL_IMAGE_NAME="${IMAGE_NAME}:${TAG}"

echo -e "${BLUE}===== n8n Docker Build Script =====${NC}"
echo -e "Building image: ${GREEN}${FULL_IMAGE_NAME}${NC}"
echo -e "${BLUE}====================================${NC}"

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

# Check if we're in the n8n repository
if [ ! -f "package.json" ] || ! grep -q "n8n-monorepo" package.json; then
    echo -e "${RED}Error: This script must be run from the n8n repository root${NC}"
    exit 1
fi

# Check if pnpm is installed
if ! command -v pnpm &> /dev/null; then
    echo -e "${RED}Error: pnpm is not installed${NC}"
    echo "Please install pnpm: npm install -g pnpm"
    exit 1
fi

# Check if docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed${NC}"
    exit 1
fi

# Check Node.js version
NODE_VERSION=$(node --version | sed 's/v//')
REQUIRED_NODE_VERSION="22.16"
if [ "$(printf '%s\n' "$REQUIRED_NODE_VERSION" "$NODE_VERSION" | sort -V | head -n1)" != "$REQUIRED_NODE_VERSION" ]; then
    echo -e "${RED}Error: Node.js version $NODE_VERSION is too old. Required: $REQUIRED_NODE_VERSION or higher${NC}"
    exit 1
fi

echo -e "${GREEN}✅ All prerequisites met${NC}"

# Build the application
echo -e "\n${YELLOW}Building n8n application...${NC}"
echo "This may take several minutes..."

if ! pnpm build:n8n > build.log 2>&1; then
    echo -e "${RED}❌ Application build failed${NC}"
    echo "Check build.log for details"
    tail -n 20 build.log
    exit 1
fi

echo -e "${GREEN}✅ Application build completed${NC}"

# Build Docker image
echo -e "\n${YELLOW}Building Docker image...${NC}"

export IMAGE_BASE_NAME="$IMAGE_NAME"
export IMAGE_TAG="$TAG"

if ! node scripts/dockerize-n8n.mjs; then
    echo -e "${RED}❌ Docker build failed${NC}"
    exit 1
fi

# Verify the image was built
if ! docker images | grep -q "$IMAGE_NAME.*$TAG"; then
    echo -e "${RED}❌ Image verification failed${NC}"
    exit 1
fi

# Get image size
IMAGE_SIZE=$(docker images "$FULL_IMAGE_NAME" --format "{{.Size}}" 2>/dev/null || echo "Unknown")

echo -e "\n${GREEN}🎉 Docker build completed successfully!${NC}"
echo -e "${GREEN}====================================${NC}"
echo -e "Image: ${GREEN}${FULL_IMAGE_NAME}${NC}"
echo -e "Size:  ${GREEN}${IMAGE_SIZE}${NC}"
echo -e "${GREEN}====================================${NC}"

# Test the image (optional)
read -p "Would you like to test the image? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "\n${YELLOW}Testing the image...${NC}"
    echo "Starting n8n container on port 5678..."
    
    # Run the container in detached mode
    CONTAINER_ID=$(docker run -d -p 5678:5678 --name n8n-test "$FULL_IMAGE_NAME")
    
    echo "Container started with ID: $CONTAINER_ID"
    echo "Waiting for n8n to start..."
    
    # Wait for n8n to be ready
    for i in {1..30}; do
        if curl -s http://localhost:5678/healthz > /dev/null 2>&1; then
            echo -e "${GREEN}✅ n8n is running successfully!${NC}"
            echo "Access n8n at: http://localhost:5678"
            echo ""
            echo "To stop the test container:"
            echo "  docker stop n8n-test && docker rm n8n-test"
            break
        fi
        sleep 2
        if [ $i -eq 30 ]; then
            echo -e "${YELLOW}⚠️  Could not verify n8n startup (timeout)${NC}"
            echo "Container logs:"
            docker logs "$CONTAINER_ID" | tail -10
            echo ""
            echo "To check manually:"
            echo "  docker logs n8n-test"
            echo "To stop the container:"
            echo "  docker stop n8n-test && docker rm n8n-test"
        fi
    done
fi

echo -e "\n${BLUE}Build script completed!${NC}"