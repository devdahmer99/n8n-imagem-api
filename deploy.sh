#!/bin/bash

# =========================================================================
# 🚀 SCRIPT DE DEPLOY ENTERPRISE - n8n Image API
# =========================================================================
# Autor: devdahmer99
# Data: 2025-06-05 18:29:24 UTC
# Versão: 2.0.0
# =========================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# =========================================================================
# 🎨 CORES E UTILIDADES
# =========================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Função para logging colorido
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" >&2
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}"
}

# =========================================================================
# 📋 CONFIGURAÇÕES
# =========================================================================
PROJECT_NAME="n8n-image-api"
PROJECT_DIR="/opt/${PROJECT_NAME}"
SERVICE_NAME="${PROJECT_NAME}"
SERVICE_USER="nodejs"
SERVICE_GROUP="nodejs"
NODE_VERSION="18"
PORT="3001"
BACKUP_DIR="/opt/backups/${PROJECT_NAME}"
LOG_DIR="/var/log/${PROJECT_NAME}"

# Detecção automática do diretório atual
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# =========================================================================
# 🔍 FUNÇÕES DE VERIFICAÇÃO
# =========================================================================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Este script deve ser executado como root (use sudo)"
        exit 1
    fi
}

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Sistema operacional não suportado"
        exit 1
    fi
    
    source /etc/os-release
    log_info "Sistema detectado: $PRETTY_NAME"
    
    case $ID in
        ubuntu|debian)
            PACKAGE_MANAGER="apt"
            ;;
        centos|rhel|fedora)
            PACKAGE_MANAGER="yum"
            ;;
        *)
            log_warning "Sistema não testado, continuando mesmo assim..."
            PACKAGE_MANAGER="apt"  # Default
            ;;
    esac
}

check_node() {
    if ! command -v node &> /dev/null; then
        log_warning "Node.js não encontrado, instalando..."
        install_node
    else
        NODE_CURRENT=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
        if [[ $NODE_CURRENT -lt $NODE_VERSION ]]; then
            log_warning "Node.js versão $NODE_CURRENT encontrada, requer versão $NODE_VERSION+"
            install_node
        else
            log_success "Node.js versão $(node --version) OK"
        fi
    fi
}

# =========================================================================
# 📦 FUNÇÕES DE INSTALAÇÃO
# =========================================================================
install_node() {
    log_info "Instalando Node.js $NODE_VERSION..."
    
    # Instalar via NodeSource
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -
    $PACKAGE_MANAGER install -y nodejs
    
    # Verificar instalação
    if command -v node &> /dev/null && command -v npm &> /dev/null; then
        log_success "Node.js $(node --version) e npm $(npm --version) instalados"
    else
        log_error "Falha na instalação do Node.js"
        exit 1
    fi
}

install_pm2() {
    if ! command -v pm2 &> /dev/null; then
        log_info "Instalando PM2..."
        npm install -g pm2@latest
        
        # Configurar PM2 para iniciar com o sistema
        pm2 startup systemd -u $SERVICE_USER --hp /home/$SERVICE_USER
        log_success "PM2 instalado e configurado"
    else
        log_success "PM2 $(pm2 --version) já instalado"
    fi
}

install_dependencies() {
    log_info "Instalando dependências do sistema..."
    
    case $PACKAGE_MANAGER in
        apt)
            apt update
            apt install -y curl wget git build-essential python3 python3-pip nginx ufw fail2ban
            ;;
        yum)
            yum update -y
            yum install -y curl wget git gcc gcc-c++ make python3 python3-pip nginx firewalld fail2ban
            ;;
    esac
    
    log_success "Dependências do sistema instaladas"
}

# =========================================================================
# 👤 FUNÇÕES DE USUÁRIO E SEGURANÇA
# =========================================================================
create_service_user() {
    if ! id "$SERVICE_USER" &>/dev/null; then
        log_info "Criando usuário de serviço: $SERVICE_USER"
        useradd -r -s /bin/false -d /home/$SERVICE_USER -m $SERVICE_USER
        usermod -a -G $SERVICE_GROUP $SERVICE_USER 2>/dev/null || groupadd $SERVICE_GROUP
        log_success "Usuário $SERVICE_USER criado"
    else
        log_info "Usuário $SERVICE_USER já existe"
    fi
}

setup_directories() {
    log_info "Configurando estrutura de diretórios..."
    
    # Criar diretórios principais
    mkdir -p $PROJECT_DIR
    mkdir -p $LOG_DIR
    mkdir -p $BACKUP_DIR
    mkdir -p $PROJECT_DIR/{logs,tmp,config}
    
    # Definir permissões
    chown -R $SERVICE_USER:$SERVICE_GROUP $PROJECT_DIR
    chown -R $SERVICE_USER:$SERVICE_GROUP $LOG_DIR
    chown -R $SERVICE_USER:$SERVICE_GROUP $BACKUP_DIR
    
    chmod 755 $PROJECT_DIR
    chmod 755 $LOG_DIR
    chmod 750 $BACKUP_DIR
    
    log_success "Estrutura de diretórios configurada"
}

# =========================================================================
# 📁 FUNÇÕES DE DEPLOYMENT
# =========================================================================
backup_existing() {
    if [[ -d $PROJECT_DIR ]] && [[ -f $PROJECT_DIR/server.js ]]; then
        log_info "Fazendo backup da instalação existente..."
        
        BACKUP_NAME="${PROJECT_NAME}-backup-$(date +%Y%m%d-%H%M%S)"
        BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"
        
        mkdir -p $BACKUP_PATH
        cp -r $PROJECT_DIR/* $BACKUP_PATH/ 2>/dev/null || true
        
        log_success "Backup salvo em: $BACKUP_PATH"
    fi
}

deploy_application() {
    log_info "Deployando aplicação..."
    
    # Copiar arquivos
    cp -r $CURRENT_DIR/* $PROJECT_DIR/
    
    # Instalar dependências
    cd $PROJECT_DIR
    npm ci --production --silent
    
    # Criar arquivo de configuração
    cat > $PROJECT_DIR/.env << EOF
# n8n Image API Configuration
# Generated on $(date)
NODE_ENV=production
PORT=$PORT
LOG_LEVEL=info
LOG_DIR=$LOG_DIR
MAX_IMAGE_SIZE=52428800
TIMEOUT=30000
RATE_LIMIT_WINDOW=900000
RATE_LIMIT_MAX=100
EOF

    # Definir permissões
    chown -R $SERVICE_USER:$SERVICE_GROUP $PROJECT_DIR
    chmod +x $PROJECT_DIR/server.js
    
    log_success "Aplicação deployada"
}

# =========================================================================
# ⚙️ FUNÇÕES DE CONFIGURAÇÃO DE SERVIÇOS
# =========================================================================
setup_systemd_service() {
    log_info "Configurando serviço systemd..."
    
    cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=n8n Image to Base64 API Service
Documentation=https://github.com/devdahmer99/n8n-image-api
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/bin/node server.js
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=mixed
KillSignal=SIGINT
TimeoutStopSec=30
Restart=always
RestartSec=10
StartLimitBurst=3
StartLimitInterval=60

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$PROJECT_DIR $LOG_DIR
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE

# Environment
Environment=NODE_ENV=production
Environment=PORT=$PORT
EnvironmentFile=-$PROJECT_DIR/.env

# Logging
StandardOutput=append:$LOG_DIR/app.log
StandardError=append:$LOG_DIR/error.log
SyslogIdentifier=$SERVICE_NAME

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    
    log_success "Serviço systemd configurado"
}

setup_pm2_config() {
    log_info "Configurando PM2..."
    
    cat > $PROJECT_DIR/ecosystem.config.js << EOF
module.exports = {
  apps: [{
    name: '$SERVICE_NAME',
    script: './server.js',
    cwd: '$PROJECT_DIR',
    user: '$SERVICE_USER',
    instances: 'max',
    exec_mode: 'cluster',
    watch: false,
    max_memory_restart: '512M',
    env: {
      NODE_ENV: 'production',
      PORT: $PORT
    },
    error_file: '$LOG_DIR/pm2-error.log',
    out_file: '$LOG_DIR/pm2-out.log',
    log_file: '$LOG_DIR/pm2-combined.log',
    time: true,
    autorestart: true,
    max_restarts: 10,
    min_uptime: '10s',
    kill_timeout: 5000,
    listen_timeout: 3000,
    shutdown_with_message: true
  }]
};
EOF

    chown $SERVICE_USER:$SERVICE_GROUP $PROJECT_DIR/ecosystem.config.js
    log_success "Configuração PM2 criada"
}

setup_nginx() {
    log_info "Configurando Nginx como proxy reverso..."
    
    cat > /etc/nginx/sites-available/$PROJECT_NAME << EOF
# n8n Image API - Nginx Configuration
# Generated on $(date)

upstream ${PROJECT_NAME}_backend {
    least_conn;
    server 127.0.0.1:$PORT max_fails=3 fail_timeout=30s;
    keepalive 32;
}

server {
    listen 80;
    server_name localhost $(hostname -f) $(hostname -I | tr ' ' '\n' | head -1);
    
    # Security headers
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=${PROJECT_NAME}:10m rate=10r/s;
    limit_req zone=${PROJECT_NAME} burst=20 nodelay;
    
    # Client settings
    client_max_body_size 60M;
    client_body_timeout 60s;
    client_header_timeout 60s;
    
    # Compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain application/json;
    
    location / {
        proxy_pass http://${PROJECT_NAME}_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 60s;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
    }
    
    # Health check endpoint (bypass rate limiting)
    location /health {
        limit_req off;
        proxy_pass http://${PROJECT_NAME}_backend;
        access_log off;
    }
    
    # Block access to sensitive files
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
}
EOF

    # Ativar site
    ln -sf /etc/nginx/sites-available/$PROJECT_NAME /etc/nginx/sites-enabled/
    
    # Testar configuração
    nginx -t
    systemctl enable nginx
    systemctl reload nginx
    
    log_success "Nginx configurado"
}

setup_firewall() {
    log_info "Configurando firewall..."
    
    if command -v ufw &> /dev/null; then
        ufw --force enable
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow ssh
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw allow from 127.0.0.1 to any port $PORT
        log_success "UFW configurado"
    elif command -v firewall-cmd &> /dev/null; then
        systemctl enable firewalld
        systemctl start firewalld
        firewall-cmd --permanent --add-service=ssh
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --permanent --add-port=$PORT/tcp --zone=internal
        firewall-cmd --reload
        log_success "Firewalld configurado"
    else
        log_warning "Nenhum firewall suportado encontrado"
    fi
}

# =========================================================================
# 🧪 FUNÇÕES DE TESTE E VALIDAÇÃO
# =========================================================================
test_deployment() {
    log_info "Testando deployment..."
    
    # Aguardar inicialização
    sleep 5
    
    # Teste de conectividade
    if curl -f -s http://localhost:$PORT/health > /dev/null; then
        log_success "API respondendo na porta $PORT"
    else
        log_error "API não está respondendo"
        return 1
    fi
    
    # Teste de conversão
    TEST_RESULT=$(curl -s -X POST http://localhost:$PORT/convert-image \
        -H "Content-Type: application/json" \
        -d '{"imageUrl":"https://httpbin.org/image/jpeg"}' | grep -o '"success":[^,]*' | cut -d':' -f2)
    
    if [[ "$TEST_RESULT" == "true" ]]; then
        log_success "Teste de conversão de imagem passou"
    else
        log_warning "Teste de conversão falhou, mas API está online"
    fi
}

# =========================================================================
# 📊 FUNÇÃO DE MONITORAMENTO
# =========================================================================
setup_monitoring() {
    log_info "Configurando monitoramento..."
    
    # Script de monitoramento
    cat > /usr/local/bin/${PROJECT_NAME}-monitor << 'EOF'
#!/bin/bash
# Monitor script for n8n-image-api

SERVICE_NAME="n8n-image-api"
PORT="3001"
LOG_FILE="/var/log/${SERVICE_NAME}/monitor.log"

check_service() {
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo "$(date): Service $SERVICE_NAME is running" >> $LOG_FILE
        return 0
    else
        echo "$(date): Service $SERVICE_NAME is down, restarting..." >> $LOG_FILE
        systemctl restart $SERVICE_NAME
        return 1
    fi
}

check_api() {
    if curl -f -s http://localhost:$PORT/health > /dev/null; then
        echo "$(date): API health check passed" >> $LOG_FILE
        return 0
    else
        echo "$(date): API health check failed" >> $LOG_FILE
        return 1
    fi
}

# Main monitoring
check_service && check_api
exit $?
EOF

    chmod +x /usr/local/bin/${PROJECT_NAME}-monitor
    
    # Cron job para monitoramento
    cat > /etc/cron.d/${PROJECT_NAME}-monitor << EOF
# Monitor n8n-image-api every 5 minutes
*/5 * * * * root /usr/local/bin/${PROJECT_NAME}-monitor
EOF

    log_success "Monitoramento configurado"
}

# =========================================================================
# 🚀 FUNÇÃO PRINCIPAL
# =========================================================================
main() {
    echo -e "${WHITE}"
    echo "=========================================="
    echo "🚀 n8n IMAGE API - ENTERPRISE DEPLOYMENT"
    echo "=========================================="
    echo "📅 Data: $(date)"
    echo "👤 Usuário: devdahmer99"
    echo "🖥️  Sistema: $(uname -s) $(uname -r)"
    echo "📁 Diretório: $CURRENT_DIR"
    echo "🎯 Destino: $PROJECT_DIR"
    echo "=========================================="
    echo -e "${NC}"
    
    # Verificações pré-deploy
    check_root
    check_os
    
    # Confirmação
    read -p "Continuar com o deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelado pelo usuário"
        exit 0
    fi
    
    # Execução das etapas
    log_info "Iniciando deployment..."
    
    install_dependencies
    check_node
    create_service_user
    setup_directories
    backup_existing
    deploy_application
    setup_systemd_service
    install_pm2
    setup_pm2_config
    setup_nginx
    setup_firewall
    setup_monitoring
    
    # Iniciar serviços
    log_info "Iniciando serviços..."
    systemctl start $SERVICE_NAME
    systemctl start nginx
    
    # Testar deployment
    test_deployment
    
    # Relatório final
    echo -e "${WHITE}"
    echo "=========================================="
    echo "🎉 DEPLOYMENT CONCLUÍDO COM SUCESSO!"
    echo "=========================================="
    echo -e "${GREEN}"
    echo "✅ API: http://localhost:$PORT"
    echo "✅ Health: http://localhost:$PORT/health"
    echo "✅ Logs: $LOG_DIR/"
    echo "✅ Config: $PROJECT_DIR/.env"
    echo -e "${BLUE}"
    echo "📋 COMANDOS ÚTEIS:"
    echo "   systemctl status $SERVICE_NAME"
    echo "   journalctl -u $SERVICE_NAME -f"
    echo "   tail -f $LOG_DIR/app.log"
    echo "   pm2 status"
    echo "   nginx -t"
    echo -e "${WHITE}"
    echo "=========================================="
    echo -e "${NC}"
}

# =========================================================================
# 🎯 EXECUÇÃO
# =========================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi