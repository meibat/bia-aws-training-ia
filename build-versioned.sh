#!/bin/bash

# Build Script Versionado - Projeto BIA
# Versão: 1.0.0
# Compatível com o build.sh original, mas com versionamento

set -e

# Configurações
ECR_REGISTRY="566362508101.dkr.ecr.us-east-1.amazonaws.com"
ECR_REPO="bia"
REGION="us-east-1"

# Cores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Build Script Versionado - Projeto BIA ===${NC}"

# Obter informações de versão
COMMIT_HASH=$(git rev-parse --short=7 HEAD)
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
VERSION="v1.0.0-${COMMIT_HASH}-${TIMESTAMP}"

echo -e "${YELLOW}Informações da Build:${NC}"
echo "  Commit Hash: $COMMIT_HASH"
echo "  Timestamp: $TIMESTAMP"
echo "  Versão: $VERSION"
echo ""

# Login no ECR
echo -e "${GREEN}[1/4] Fazendo login no ECR...${NC}"
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

# Build da imagem
echo -e "${GREEN}[2/4] Fazendo build da imagem...${NC}"
docker build -t $ECR_REPO .

# Tag das imagens
echo -e "${GREEN}[3/4] Criando tags...${NC}"
docker tag $ECR_REPO:latest $ECR_REGISTRY/$ECR_REPO:latest
docker tag $ECR_REPO:latest $ECR_REGISTRY/$ECR_REPO:$VERSION
docker tag $ECR_REPO:latest $ECR_REGISTRY/$ECR_REPO:$COMMIT_HASH

# Push das imagens
echo -e "${GREEN}[4/4] Fazendo push para ECR...${NC}"
docker push $ECR_REGISTRY/$ECR_REPO:latest
docker push $ECR_REGISTRY/$ECR_REPO:$VERSION
docker push $ECR_REGISTRY/$ECR_REPO:$COMMIT_HASH

echo -e "${GREEN}Build concluído com sucesso!${NC}"
echo ""
echo -e "${YELLOW}Imagens criadas:${NC}"
echo "  - $ECR_REGISTRY/$ECR_REPO:latest"
echo "  - $ECR_REGISTRY/$ECR_REPO:$VERSION"
echo "  - $ECR_REGISTRY/$ECR_REPO:$COMMIT_HASH"

# Salvar informações da build
echo "$VERSION" > .last-build-version
echo "$COMMIT_HASH" > .last-build-commit
echo "$ECR_REGISTRY/$ECR_REPO:$VERSION" > .last-build-uri
echo "$TIMESTAMP" > .last-build-timestamp

echo ""
echo -e "${BLUE}Para fazer deploy, execute:${NC}"
echo "  ./deploy-ecs-fixed.sh deploy"
