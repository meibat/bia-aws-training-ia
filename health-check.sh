#!/bin/bash

# Health Check Script - Projeto BIA
# Versão: 1.0.0
# Descrição: Script para verificar a saúde da aplicação

set -e

# Configurações padrão
DEFAULT_REGION="us-east-1"
DEFAULT_CLUSTER="cluster-bia"
DEFAULT_SERVICE="service-bia"
DEFAULT_ENDPOINT=""

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Função para log
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

# Função para exibir help
show_help() {
    cat << EOF
${BLUE}=== Health Check Script - Projeto BIA ===${NC}

${YELLOW}DESCRIÇÃO:${NC}
    Script para verificar a saúde da aplicação BIA no ECS

${YELLOW}USO:${NC}
    $0 [OPÇÕES]

${YELLOW}OPÇÕES:${NC}
    -r, --region REGION         Região AWS (padrão: $DEFAULT_REGION)
    -c, --cluster CLUSTER       Nome do cluster ECS (padrão: $DEFAULT_CLUSTER)
    -s, --service SERVICE       Nome do serviço ECS (padrão: $DEFAULT_SERVICE)
    -e, --endpoint ENDPOINT     Endpoint da aplicação para teste HTTP
    -h, --help                  Exibe esta ajuda

${YELLOW}EXEMPLOS:${NC}
    # Verificação básica do ECS
    $0

    # Verificação com endpoint específico
    $0 -e http://bia-alb-123456789.us-east-1.elb.amazonaws.com

EOF
}

# Função para verificar status do serviço ECS
check_ecs_service() {
    log "INFO" "Verificando status do serviço ECS..."
    
    local service_info=$(aws ecs describe-services \
        --cluster "$CLUSTER" \
        --services "$SERVICE" \
        --region "$REGION" \
        --query 'services[0]' \
        --output json 2>/dev/null)
    
    if [ $? -ne 0 ] || [ "$service_info" = "null" ]; then
        log "ERROR" "Serviço não encontrado: $SERVICE"
        return 1
    fi
    
    local running_count=$(echo "$service_info" | jq -r '.runningCount')
    local desired_count=$(echo "$service_info" | jq -r '.desiredCount')
    local status=$(echo "$service_info" | jq -r '.status')
    local task_definition=$(echo "$service_info" | jq -r '.taskDefinition' | cut -d'/' -f2)
    
    echo -e "\n${BLUE}=== Status do Serviço ECS ===${NC}"
    echo "Serviço: $SERVICE"
    echo "Status: $status"
    echo "Tasks Desejadas: $desired_count"
    echo "Tasks Rodando: $running_count"
    echo "Task Definition: $task_definition"
    
    if [ "$running_count" -eq "$desired_count" ] && [ "$status" = "ACTIVE" ]; then
        log "INFO" "Serviço ECS está saudável"
        return 0
    else
        log "WARN" "Serviço ECS pode ter problemas"
        return 1
    fi
}

# Função para verificar tasks
check_tasks() {
    log "INFO" "Verificando tasks do serviço..."
    
    local task_arns=$(aws ecs list-tasks \
        --cluster "$CLUSTER" \
        --service-name "$SERVICE" \
        --region "$REGION" \
        --query 'taskArns' \
        --output text 2>/dev/null)
    
    if [ -z "$task_arns" ] || [ "$task_arns" = "None" ]; then
        log "WARN" "Nenhuma task encontrada"
        return 1
    fi
    
    local task_details=$(aws ecs describe-tasks \
        --cluster "$CLUSTER" \
        --tasks $task_arns \
        --region "$REGION" \
        --query 'tasks[*].[taskArn,lastStatus,healthStatus,createdAt]' \
        --output table 2>/dev/null)
    
    echo -e "\n${BLUE}=== Status das Tasks ===${NC}"
    echo "$task_details"
    
    # Verificar se todas as tasks estão RUNNING
    local running_tasks=$(aws ecs describe-tasks \
        --cluster "$CLUSTER" \
        --tasks $task_arns \
        --region "$REGION" \
        --query 'tasks[?lastStatus==`RUNNING`] | length(@)' \
        --output text 2>/dev/null)
    
    local total_tasks=$(echo $task_arns | wc -w)
    
    if [ "$running_tasks" -eq "$total_tasks" ]; then
        log "INFO" "Todas as tasks estão rodando"
        return 0
    else
        log "WARN" "$running_tasks de $total_tasks tasks estão rodando"
        return 1
    fi
}

# Função para verificar endpoint HTTP
check_http_endpoint() {
    if [ -z "$ENDPOINT" ]; then
        log "INFO" "Endpoint não especificado, pulando verificação HTTP"
        return 0
    fi
    
    log "INFO" "Verificando endpoint HTTP: $ENDPOINT"
    
    # Testar endpoint principal
    local http_status=$(curl -s -o /dev/null -w "%{http_code}" "$ENDPOINT" --max-time 10 2>/dev/null || echo "000")
    
    echo -e "\n${BLUE}=== Status HTTP ===${NC}"
    echo "Endpoint: $ENDPOINT"
    echo "Status Code: $http_status"
    
    if [ "$http_status" = "200" ]; then
        log "INFO" "Endpoint HTTP está respondendo corretamente"
        
        # Testar endpoint de versão se disponível
        local version_endpoint="$ENDPOINT/api/versao"
        local version_status=$(curl -s -o /dev/null -w "%{http_code}" "$version_endpoint" --max-time 5 2>/dev/null || echo "000")
        
        if [ "$version_status" = "200" ]; then
            local version_info=$(curl -s "$version_endpoint" --max-time 5 2>/dev/null || echo "N/A")
            echo "Endpoint de versão: OK"
            echo "Informações: $version_info"
        fi
        
        return 0
    else
        log "ERROR" "Endpoint HTTP não está respondendo corretamente (Status: $http_status)"
        return 1
    fi
}

# Função para verificar logs recentes
check_recent_logs() {
    log "INFO" "Verificando logs recentes..."
    
    # Tentar encontrar log group
    local log_group="/ecs/$SERVICE"
    
    local log_streams=$(aws logs describe-log-streams \
        --log-group-name "$log_group" \
        --order-by LastEventTime \
        --descending \
        --max-items 1 \
        --region "$REGION" \
        --query 'logStreams[0].logStreamName' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$log_streams" ] && [ "$log_streams" != "None" ]; then
        echo -e "\n${BLUE}=== Logs Recentes ===${NC}"
        aws logs get-log-events \
            --log-group-name "$log_group" \
            --log-stream-name "$log_streams" \
            --start-time $(date -d '5 minutes ago' +%s)000 \
            --region "$REGION" \
            --query 'events[-5:].message' \
            --output text 2>/dev/null || log "WARN" "Não foi possível obter logs recentes"
    else
        log "WARN" "Log group não encontrado: $log_group"
    fi
}

# Parsing de argumentos
REGION="$DEFAULT_REGION"
CLUSTER="$DEFAULT_CLUSTER"
SERVICE="$DEFAULT_SERVICE"
ENDPOINT="$DEFAULT_ENDPOINT"

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
        -e|--endpoint)
            ENDPOINT="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log "ERROR" "Opção desconhecida: $1"
            show_help
            exit 1
            ;;
    esac
done

# Executar verificações
echo -e "${BLUE}=== Health Check - Projeto BIA ===${NC}"
echo "Cluster: $CLUSTER"
echo "Serviço: $SERVICE"
echo "Região: $REGION"
if [ -n "$ENDPOINT" ]; then
    echo "Endpoint: $ENDPOINT"
fi
echo ""

# Contadores de sucesso
success_count=0
total_checks=0

# Verificar serviço ECS
total_checks=$((total_checks + 1))
if check_ecs_service; then
    success_count=$((success_count + 1))
fi

# Verificar tasks
total_checks=$((total_checks + 1))
if check_tasks; then
    success_count=$((success_count + 1))
fi

# Verificar endpoint HTTP se especificado
if [ -n "$ENDPOINT" ]; then
    total_checks=$((total_checks + 1))
    if check_http_endpoint; then
        success_count=$((success_count + 1))
    fi
fi

# Verificar logs (não conta para o score de saúde)
check_recent_logs

# Resultado final
echo ""
echo -e "${BLUE}=== Resultado Final ===${NC}"
echo "Verificações bem-sucedidas: $success_count de $total_checks"

if [ "$success_count" -eq "$total_checks" ]; then
    log "INFO" "Aplicação está saudável! ✅"
    exit 0
elif [ "$success_count" -gt 0 ]; then
    log "WARN" "Aplicação tem alguns problemas ⚠️"
    exit 1
else
    log "ERROR" "Aplicação tem problemas críticos ❌"
    exit 2
fi
