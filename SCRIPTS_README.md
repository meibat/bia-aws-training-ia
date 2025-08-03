# Scripts de Deploy - Projeto BIA

Este documento descreve os scripts disponíveis para build, deploy e monitoramento da aplicação BIA no Amazon ECS.

## 📋 Scripts Disponíveis

### 1. `build-versioned.sh` - Build Versionado
Script para fazer build da aplicação Docker com versionamento automático.

**Características:**
- Versionamento baseado no `package.json` + commit hash + timestamp
- Push automático para ECR com múltiplas tags
- Criação de arquivos de controle para rastreamento

**Uso:**
```bash
./build-versioned.sh
```

**Exemplo de saída:**
```
=== Build Script Versionado - Projeto BIA ===
Informações da Build:
  Package Version: 4.2.0
  Commit Hash: 5e49105
  Timestamp: 20250803-184230
  Versão: v4.2.0-5e49105-20250803-184230

[1/4] Fazendo login no ECR...
[2/4] Fazendo build da imagem...
[3/4] Criando tags...
[4/4] Fazendo push para ECR...

Build concluído com sucesso!

Imagens criadas:
  - 566362508101.dkr.ecr.us-east-1.amazonaws.com/bia:latest
  - 566362508101.dkr.ecr.us-east-1.amazonaws.com/bia:v4.2.0-5e49105-20250803-184230
  - 566362508101.dkr.ecr.us-east-1.amazonaws.com/bia:5e49105
```

### 2. `deploy-ecs-fixed.sh` - Deploy Completo
Script principal para gerenciar deploys no ECS com funcionalidades avançadas.

**Comandos disponíveis:**
- `build` - Faz build e push da imagem
- `deploy` - Deploy da aplicação no ECS
- `rollback` - Rollback para versão anterior
- `list` - Lista versões disponíveis
- `help` - Exibe ajuda completa

**Uso básico:**
```bash
# Deploy da última versão buildada
./deploy-ecs-fixed.sh deploy

# Build e deploy
./deploy-ecs-fixed.sh build
./deploy-ecs-fixed.sh deploy

# Rollback para versão específica
./deploy-ecs-fixed.sh rollback -v v4.2.0-abc123f-20250803-175300

# Listar versões disponíveis
./deploy-ecs-fixed.sh list
```

**Opções avançadas:**
```bash
# Deploy em região específica
./deploy-ecs-fixed.sh deploy -r us-west-2

# Deploy em cluster específico
./deploy-ecs-fixed.sh deploy -c meu-cluster -s meu-service

# Ajuda completa
./deploy-ecs-fixed.sh help
```

### 3. `build-and-deploy.sh` - Script Combinado
Script que executa build e deploy em sequência automaticamente.

**Uso:**
```bash
./build-and-deploy.sh
```

**Funcionalidades:**
- Executa build versionado
- Aguarda 3 segundos
- Executa deploy automaticamente
- Mostra informações finais do deploy

### 4. `health-check.sh` - Verificação de Saúde
Script para verificar a saúde da aplicação no ECS.

**Uso:**
```bash
# Verificação básica
./health-check.sh

# Com endpoint específico
./health-check.sh -e http://meu-alb.amazonaws.com

# Ajuda
./health-check.sh --help
```

**Verificações realizadas:**
- Status do serviço ECS
- Status das tasks
- Teste HTTP (se endpoint fornecido)
- Logs recentes

## 🏗️ Estrutura de Versionamento

As imagens são taggeadas com o seguinte padrão:
```
v{package-version}-{commit-hash}-{timestamp}
```

**Exemplo:**
```
v4.2.0-5e49105-20250803-184230
```

**Tags criadas:**
- `v4.2.0-5e49105-20250803-184230` - Versão completa
- `5e49105` - Apenas commit hash
- `latest` - Sempre aponta para a última build

## 📁 Arquivos de Controle

Os scripts criam arquivos de controle para rastreamento:

### Build
- `.last-build-version` - Última versão buildada
- `.last-build-commit` - Commit hash da última build
- `.last-build-uri` - URI completa da imagem
- `.last-build-timestamp` - Timestamp da build

### Deploy
- `.last-deploy-version` - Última versão deployada
- `.last-deploy-revision` - Revisão da task definition
- `.last-deploy-timestamp` - Timestamp do deploy

## ⚙️ Configurações Padrão

### Recursos AWS
- **Região:** `us-east-1`
- **ECR Repository:** `bia`
- **ECS Cluster:** `cluster-bia`
- **ECS Service:** `service-bia`
- **Task Definition:** `task-def-bia`

### Personalização
Todos os scripts aceitam parâmetros para personalizar as configurações:

```bash
# Exemplo com configurações customizadas
./deploy-ecs-fixed.sh deploy \
  -r us-west-2 \
  -c meu-cluster \
  -s meu-service \
  -t minha-task-def \
  -e meu-repo
```

## 🚀 Fluxo de Trabalho Recomendado

### Deploy Normal
```bash
# 1. Build da aplicação
./build-versioned.sh

# 2. Deploy
./deploy-ecs-fixed.sh deploy

# 3. Verificar saúde
./health-check.sh
```

### Deploy Rápido
```bash
# Build + Deploy automático
./build-and-deploy.sh

# Verificar saúde
./health-check.sh
```

### Rollback
```bash
# 1. Listar versões disponíveis
./deploy-ecs-fixed.sh list

# 2. Fazer rollback
./deploy-ecs-fixed.sh rollback -v v4.1.0-abc123f-20250803-120000

# 3. Verificar saúde
./health-check.sh
```

## 🔧 Pré-requisitos

### Ferramentas necessárias:
- AWS CLI configurado
- Docker instalado e rodando
- Git (para commit hash)
- jq (para parsing JSON)
- curl (para health checks HTTP)

### Permissões AWS necessárias:
- ECR: `GetAuthorizationToken`, `BatchCheckLayerAvailability`, `GetDownloadUrlForLayer`, `BatchGetImage`, `PutImage`
- ECS: `DescribeServices`, `DescribeTasks`, `DescribeTaskDefinition`, `RegisterTaskDefinition`, `UpdateService`
- CloudWatch Logs: `DescribeLogGroups`, `DescribeLogStreams`, `GetLogEvents`

## 🐛 Troubleshooting

### Problemas Comuns

**1. Erro de login no ECR**
```bash
# Verificar credenciais AWS
aws sts get-caller-identity

# Fazer login manual
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 566362508101.dkr.ecr.us-east-1.amazonaws.com
```

**2. Task definition não encontrada**
```bash
# Listar task definitions
aws ecs list-task-definitions --family-prefix task-def-bia
```

**3. Serviço não estabiliza**
```bash
# Verificar logs do serviço
./health-check.sh

# Verificar eventos do serviço
aws ecs describe-services --cluster cluster-bia --services service-bia --query 'services[0].events[0:5]'
```

### Logs e Debug

Para debug detalhado, os scripts mostram informações coloridas:
- 🟢 **Verde:** Informações e sucessos
- 🟡 **Amarelo:** Avisos
- 🔴 **Vermelho:** Erros
- 🔵 **Azul:** Debug e títulos

## 📝 Notas Importantes

1. **Backup:** Os scripts sempre mantêm a tag `latest` e versões anteriores para rollback
2. **Segurança:** Credenciais são obtidas via AWS CLI, não hardcoded
3. **Monitoramento:** Use o `health-check.sh` regularmente para monitorar a aplicação
4. **Versionamento:** O versionamento é automático baseado no Git e package.json

## 🤝 Contribuição

Para melhorias nos scripts:
1. Teste em ambiente de desenvolvimento
2. Mantenha a compatibilidade com a estrutura existente
3. Documente mudanças neste README
4. Siga o padrão de cores e logs dos scripts existentes
