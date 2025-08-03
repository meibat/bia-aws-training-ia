#!/bin/bash

# Script Combinado Build + Deploy - Projeto BIA
# Versão: 1.0.0
# Descrição: Script que executa build e deploy em sequência

set -e

# Cores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Build + Deploy - Projeto BIA ===${NC}"

# Função para log
log() {
    local level=$1
    shift
    case $level in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $*" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $*" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $*" ;;
    esac
}

# Verificar se os scripts existem
if [ ! -f "./build-versioned.sh" ]; then
    log "ERROR" "Script build-versioned.sh não encontrado"
    exit 1
fi

if [ ! -f "./deploy-ecs-fixed.sh" ]; then
    log "ERROR" "Script deploy-ecs-fixed.sh não encontrado"
    exit 1
fi

# Verificar se os scripts são executáveis
if [ ! -x "./build-versioned.sh" ]; then
    log "WARN" "Tornando build-versioned.sh executável..."
    chmod +x ./build-versioned.sh
fi

if [ ! -x "./deploy-ecs-fixed.sh" ]; then
    log "WARN" "Tornando deploy-ecs-fixed.sh executável..."
    chmod +x ./deploy-ecs-fixed.sh
fi

# Executar build
log "INFO" "Iniciando processo de build..."
echo ""
if ./build-versioned.sh; then
    log "INFO" "Build concluído com sucesso!"
else
    log "ERROR" "Falha no build. Abortando deploy."
    exit 1
fi

echo ""
log "INFO" "Aguardando 3 segundos antes do deploy..."
sleep 3

# Executar deploy
log "INFO" "Iniciando processo de deploy..."
echo ""
if ./deploy-ecs-fixed.sh deploy; then
    log "INFO" "Deploy concluído com sucesso!"
else
    log "ERROR" "Falha no deploy."
    exit 1
fi

echo ""
log "INFO" "Processo completo finalizado com sucesso!"

# Mostrar informações finais
if [ -f ".last-deploy-version" ]; then
    echo ""
    echo -e "${BLUE}=== Informações do Deploy ===${NC}"
    echo "Versão deployada: $(cat .last-deploy-version)"
    echo "Revisão da task: $(cat .last-deploy-revision 2>/dev/null || echo 'N/A')"
    echo "Timestamp: $(cat .last-deploy-timestamp 2>/dev/null || echo 'N/A')"
fi
