#!/bin/bash

# Script de Deploy ECS - Projeto BIA (Versão Corrigida)
# Versão: 1.1.0
# Autor: Amazon Q
# Descrição: Script para build e deploy da aplicação BIA no ECS com versionamento aprimorado

set -e

# Configurações padrão
DEFAULT_REGION="us-east-1"
DEFAULT_CLUSTER="cluster-bia"
DEFAULT_SERVICE="service-bia"
DEFAULT_TASK_DEFINITION="task-def-bia"
DEFAULT_ECR_REPO="bia"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para exibir help
show_help() {
    cat << EOF
${BLUE}=== Script de Deploy ECS - Projeto BIA (Versão Corrigida) ===${NC}

${YELLOW}DESCRIÇÃO:${NC}
    Script para build e deploy da aplicação BIA no Amazon ECS com versionamento
    por commit hash + timestamp, permitindo rollbacks para versões anteriores.

${YELLOW}USO:${NC}
    $0 [OPÇÕES] COMANDO

${YELLOW}COMANDOS:${NC}
    build       Faz o build da imagem Docker e push para ECR
    deploy      Faz o deploy da aplicação no ECS
    rollback    Faz rollback para uma versão anterior
    list        Lista as últimas 10 versões disponíveis no ECR
    help        Exibe esta ajuda

${YELLOW}OPÇÕES:${NC}
    -r, --region REGION         Região AWS (padrão: $DEFAULT_REGION)
    -c, --cluster CLUSTER       Nome do cluster ECS (padrão: $DEFAULT_CLUSTER)
    -s, --service SERVICE       Nome do serviço ECS (padrão: $DEFAULT_SERVICE)
    -t, --task-def TASK_DEF     Nome da task definition (padrão: $DEFAULT_TASK_DEFINITION)
    -e, --ecr-repo REPO         Nome do repositório ECR (padrão: $DEFAULT_ECR_REPO)
    -v, --version VERSION       Versão específica para rollback
    -h, --help                  Exibe esta ajuda

${YELLOW}EXEMPLOS:${NC}
    # Build e push da imagem atual
    $0 build

    # Deploy da versão atual
    $0 deploy

    # Build e deploy em sequência
    $0 build && $0 deploy

    # Rollback para versão específica
    $0 rollback -v v4.2.0-abc123f-20250803-175300

    # Listar versões disponíveis
    $0 list

${YELLOW}ESTRUTURA DE VERSIONAMENTO:${NC}
    As imagens são taggeadas com: v{package-version}-{commit-hash}-{timestamp}
    Exemplo: v4.2.0-abc123f-20250803-175300
    
    Também são criadas tags adicionais:
    - latest: Sempre aponta para a última build
    - {commit-hash}: Tag simples com apenas o commit

EOF
}

# Função para log colorido
log() {
    local level=$1
    shift
    case $level in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $*" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $*" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $*" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $*" ;;
    esac
}

# Função para verificar pré-requisitos
check_prerequisites() {
    log "INFO" "Verificando pré-requisitos..."
    
    # Verificar AWS CLI
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI não encontrado. Instale o AWS CLI."
        exit 1
    fi
    
    # Verificar Docker
    if ! command -v docker &> /dev/null; then
        log "ERROR" "Docker não encontrado. Instale o Docker."
        exit 1
    fi
    
    # Verificar se Docker está rodando
    if ! docker info &> /dev/null; then
        log "ERROR" "Docker não está rodando. Inicie o Docker."
        exit 1
    fi
    
    # Verificar se está em um repositório Git
    if ! git rev-parse --git-dir &> /dev/null; then
        log "ERROR" "Não está em um repositório Git."
        exit 1
    fi
    
    log "INFO" "Pré-requisitos verificados com sucesso!"
}

# Função para obter informações de versão
get_version_info() {
    local commit_hash=$(git rev-parse --short=7 HEAD)
    local timestamp=$(date +%Y%m%d-%H%M%S)
    # Tentar obter versão do package.json, senão usar padrão
    local package_version="1.0.0"
    if [ -f "package.json" ] && command -v jq &> /dev/null; then
        package_version=$(jq -r '.version' package.json 2>/dev/null || echo "1.0.0")
    fi
    local version="v${package_version}-${commit_hash}-${timestamp}"
    
    echo "$version|$commit_hash|$timestamp|$package_version"
}

# Função para obter account ID
get_account_id() {
    aws sts get-caller-identity --query Account --output text --region "$REGION"
}

# Função para fazer login no ECR
ecr_login() {
    log "INFO" "Fazendo login no ECR..."
    aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
}

# Função para build da imagem
build_image() {
    log "INFO" "Iniciando build da imagem..."
    
    local version_info=$(get_version_info)
    local version=$(echo "$version_info" | cut -d'|' -f1)
    local commit_hash=$(echo "$version_info" | cut -d'|' -f2)
    local timestamp=$(echo "$version_info" | cut -d'|' -f3)
    local package_version=$(echo "$version_info" | cut -d'|' -f4)
    
    local ecr_base="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_REPO"
    
    log "INFO" "Package Version: $package_version"
    log "INFO" "Versão completa: $version"
    log "INFO" "Commit hash: $commit_hash"
    log "INFO" "Timestamp: $timestamp"
    
    # Verificar se Dockerfile existe
    if [ ! -f "Dockerfile" ]; then
        log "ERROR" "Dockerfile não encontrado no diretório atual."
        exit 1
    fi
    
    # Build da imagem com múltiplas tags
    log "INFO" "Fazendo build da imagem Docker..."
    docker build \
        -t "$ECR_REPO:$version" \
        -t "$ECR_REPO:$commit_hash" \
        -t "$ECR_REPO:latest" \
        -t "$ecr_base:$version" \
        -t "$ecr_base:$commit_hash" \
        -t "$ecr_base:latest" \
        .
    
    # Login no ECR
    ecr_login
    
    # Push de todas as tags
    log "INFO" "Fazendo push das imagens para ECR..."
    docker push "$ecr_base:$version"
    docker push "$ecr_base:$commit_hash"
    docker push "$ecr_base:latest"
    
    log "INFO" "Build concluído com sucesso!"
    log "INFO" "Imagens disponíveis:"
    log "INFO" "  - $ecr_base:$version (versão completa)"
    log "INFO" "  - $ecr_base:$commit_hash (commit hash)"
    log "INFO" "  - $ecr_base:latest (última versão)"
    
    # Salvar informações da última build
    echo "$version" > .last-build-version
    echo "$commit_hash" > .last-build-commit
    echo "$ecr_base:$version" > .last-build-uri
    echo "$timestamp" > .last-build-timestamp
}

# Função para criar nova task definition
create_task_definition() {
    local image_tag=$1
    local image_uri="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_REPO:$image_tag"
    
    log "INFO" "Criando nova task definition..." >&2
    log "DEBUG" "Image URI: $image_uri" >&2
    
    # Obter task definition atual
    local current_task_def=$(aws ecs describe-task-definition \
        --task-definition "$TASK_DEFINITION" \
        --region "$REGION" \
        --query 'taskDefinition' \
        --output json)
    
    if [ $? -ne 0 ]; then
        log "ERROR" "Falha ao obter task definition atual: $TASK_DEFINITION" >&2
        exit 1
    fi
    
    # Atualizar image URI na task definition
    local new_task_def=$(echo "$current_task_def" | jq --arg image "$image_uri" '
        .containerDefinitions[0].image = $image |
        del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .placementConstraints, .compatibilities, .registeredAt, .registeredBy)
    ')
    
    # Registrar nova task definition
    local register_output=$(aws ecs register-task-definition \
        --region "$REGION" \
        --cli-input-json "$new_task_def" \
        --output json)
    
    if [ $? -ne 0 ]; then
        log "ERROR" "Falha ao registrar nova task definition" >&2
        exit 1
    fi
    
    local new_revision=$(echo "$register_output" | jq -r '.taskDefinition.revision')
    
    log "INFO" "Nova task definition criada: $TASK_DEFINITION:$new_revision" >&2
    # Retornar apenas o número da revisão
    echo "$new_revision"
}

# Função para fazer deploy
deploy_application() {
    local image_tag=""
    
    # Se não foi especificada uma versão, tentar usar a última build
    if [ -z "$VERSION" ]; then
        if [ -f ".last-build-version" ]; then
            image_tag=$(cat .last-build-version)
            log "INFO" "Usando última build: $image_tag"
        elif [ -f ".last-build-commit" ]; then
            image_tag=$(cat .last-build-commit)
            log "INFO" "Usando commit da última build: $image_tag"
        else
            # Usar 'latest' como fallback
            log "WARN" "Nenhuma build local encontrada. Tentando usar 'latest'..."
            image_tag="latest"
        fi
    else
        image_tag="$VERSION"
        log "INFO" "Usando versão especificada: $image_tag"
    fi
    
    # Verificar se a imagem existe no ECR
    local image_exists=$(aws ecr describe-images \
        --repository-name "$ECR_REPO" \
        --image-ids imageTag="$image_tag" \
        --region "$REGION" \
        --query 'imageDetails[0].imageTags[0]' \
        --output text 2>/dev/null)
    
    if [ "$image_exists" = "None" ] || [ -z "$image_exists" ]; then
        log "ERROR" "Imagem não encontrada no ECR: $ECR_REPO:$image_tag"
        log "INFO" "Execute '$0 build' para criar uma nova versão ou 'list' para ver versões disponíveis"
        exit 1
    fi
    
    log "INFO" "Iniciando deploy da aplicação..."
    log "INFO" "Imagem: $ECR_REPO:$image_tag"
    
    # Criar nova task definition
    local new_revision
    new_revision=$(create_task_definition "$image_tag")
    
    if [ -z "$new_revision" ]; then
        log "ERROR" "Falha ao criar nova task definition"
        exit 1
    fi
    
    # Atualizar serviço ECS
    log "INFO" "Atualizando serviço ECS..."
    aws ecs update-service \
        --cluster "$CLUSTER" \
        --service "$SERVICE" \
        --task-definition "$TASK_DEFINITION:$new_revision" \
        --region "$REGION" \
        --query 'service.serviceName' \
        --output text
    
    if [ $? -ne 0 ]; then
        log "ERROR" "Falha ao atualizar serviço ECS"
        exit 1
    fi
    
    log "INFO" "Deploy iniciado com sucesso!"
    log "INFO" "Aguardando estabilização do serviço..."
    
    # Aguardar estabilização
    aws ecs wait services-stable \
        --cluster "$CLUSTER" \
        --services "$SERVICE" \
        --region "$REGION"
    
    if [ $? -eq 0 ]; then
        log "INFO" "Deploy concluído com sucesso!"
        log "INFO" "Versão deployada: $image_tag"
        
        # Salvar informações do último deploy
        echo "$image_tag" > .last-deploy-version
        echo "$new_revision" > .last-deploy-revision
        date +%Y%m%d-%H%M%S > .last-deploy-timestamp
    else
        log "WARN" "Timeout aguardando estabilização. Verifique o status manualmente."
    fi
}

# Função para listar versões
list_versions() {
    log "INFO" "Listando versões disponíveis no ECR..."
    
    echo -e "\n${BLUE}=== Últimas 15 versões no ECR ===${NC}"
    aws ecr describe-images \
        --repository-name "$ECR_REPO" \
        --region "$REGION" \
        --query 'sort_by(imageDetails,&imagePushedAt)[-15:].[imageTags[0],imagePushedAt,imageSizeInBytes]' \
        --output table
    
    # Mostrar informações da última build local
    if [ -f ".last-build-version" ]; then
        echo -e "\n${GREEN}=== Última Build Local ===${NC}"
        echo "Versão: $(cat .last-build-version 2>/dev/null || echo 'N/A')"
        echo "Commit: $(cat .last-build-commit 2>/dev/null || echo 'N/A')"
        echo "Timestamp: $(cat .last-build-timestamp 2>/dev/null || echo 'N/A')"
    fi
    
    # Mostrar informações do último deploy
    if [ -f ".last-deploy-version" ]; then
        echo -e "\n${YELLOW}=== Último Deploy ===${NC}"
        echo "Versão: $(cat .last-deploy-version 2>/dev/null || echo 'N/A')"
        echo "Revisão: $(cat .last-deploy-revision 2>/dev/null || echo 'N/A')"
        echo "Timestamp: $(cat .last-deploy-timestamp 2>/dev/null || echo 'N/A')"
    fi
}

# Função para rollback
rollback_application() {
    if [ -z "$VERSION" ]; then
        log "ERROR" "Versão não especificada para rollback. Use -v ou --version"
        log "INFO" "Execute '$0 list' para ver versões disponíveis"
        exit 1
    fi
    
    log "INFO" "Iniciando rollback para versão: $VERSION"
    deploy_application
}

# Parsing de argumentos
REGION="$DEFAULT_REGION"
CLUSTER="$DEFAULT_CLUSTER"
SERVICE="$DEFAULT_SERVICE"
TASK_DEFINITION="$DEFAULT_TASK_DEFINITION"
ECR_REPO="$DEFAULT_ECR_REPO"
VERSION=""
COMMAND=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -c|--cluster)
            CLUSTER="$2"
            shift 2
            ;;
        -s|--service)
            SERVICE="$2"
            shift 2
            ;;
        -t|--task-def)
            TASK_DEFINITION="$2"
            shift 2
            ;;
        -e|--ecr-repo)
            ECR_REPO="$2"
            shift 2
            ;;
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        build|deploy|rollback|list|help)
            COMMAND="$1"
            shift
            ;;
        *)
            log "ERROR" "Opção desconhecida: $1"
            show_help
            exit 1
            ;;
    esac
done

# Verificar se comando foi especificado
if [ -z "$COMMAND" ]; then
    log "ERROR" "Comando não especificado"
    show_help
    exit 1
fi

# Obter Account ID
ACCOUNT_ID=$(get_account_id)

# Executar comando
case $COMMAND in
    "build")
        check_prerequisites
        build_image
        ;;
    "deploy")
        check_prerequisites
        deploy_application
        ;;
    "rollback")
        check_prerequisites
        rollback_application
        ;;
    "list")
        list_versions
        ;;
    "help")
        show_help
        ;;
    *)
        log "ERROR" "Comando inválido: $COMMAND"
        show_help
        exit 1
        ;;
esac
