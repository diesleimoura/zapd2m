#!/bin/bash

# ============================================================
#   Instalador Automático — zapd2m
#   Versão 2.0
# ============================================================

set -e

# ─── Cores ───────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

# ─── UI ──────────────────────────────────────────────────────
print_banner() {
  clear
  echo -e "${CYAN}"
  echo "   ██████╗ ██╗ ██████╗██╗  ██╗ █████╗ ████████╗"
  echo "   ██╔══██╗██║██╔════╝██║  ██║██╔══██╗╚══██╔══╝"
  echo "   ██║  ██║██║██║     ███████║███████║   ██║   "
  echo "   ██║  ██║██║██║     ██╔══██║██╔══██║   ██║   "
  echo "   ██████╔╝██║╚██████╗██║  ██║██║  ██║   ██║   "
  echo "   ╚═════╝ ╚═╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝  "
  echo ""
  echo "   ██████╗ ██╗     ██╗   ██╗███████╗ ██████╗  ██████╗ "
  echo "   ██╔══██╗██║     ██║   ██║██╔════╝██╔════╝ ██╔═══██╗"
  echo "   ██████╔╝██║     ██║   ██║███████╗██║  ███╗██║   ██║"
  echo "   ██╔═══╝ ██║     ██║   ██║╚════██║██║   ██║██║   ██║"
  echo "   ██║     ███████╗╚██████╔╝███████║╚██████╔╝╚██████╔╝"
  echo "   ╚═╝     ╚══════╝ ╚═════╝ ╚══════╝ ╚═════╝  ╚═════╝ "
  echo -e "${NC}"
  echo -e "  ${WHITE}${BOLD}Instalador Automático v2.1${NC}"
  echo -e "  ${BLUE}─────────────────────────────────────────────${NC}"
  echo ""
}

step()      { echo -e "\n${CYAN}${BOLD}[PASSO $1]${NC} ${WHITE}$2${NC}\n${BLUE}──────────────────────────────────────────────${NC}"; }
ok()        { echo -e "  ${GREEN}✔${NC} $1"; }
warn()      { echo -e "  ${YELLOW}⚠${NC}  $1"; }
info()      { echo -e "  ${BLUE}ℹ${NC}  $1"; }
ask()       { echo -en "  ${WHITE}▶ $1: ${NC}"; }
separator() { echo -e "\n${BLUE}──────────────────────────────────────────────${NC}\n"; }

spinner() {
  local pid=$1 msg=$2 delay=0.1 i=0
  local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
  while kill -0 $pid 2>/dev/null; do
    echo -en "\r  ${CYAN}${frames[$i]}${NC} $msg"
    i=$(( (i+1) % ${#frames[@]} ))
    sleep $delay
  done
  echo -e "\r  ${GREEN}✔${NC} $msg"
}

# ─── PASSO 1 — Dependências do sistema ───────────────────────
install_system_deps() {
  step "1" "Instalando dependências do sistema"

  info "Atualizando lista de pacotes..."
  apt-get update -qq &>/dev/null
  ok "Lista atualizada"

  # curl
  if ! command -v curl &>/dev/null; then
    info "Instalando curl..."
    apt-get install -y curl &>/dev/null
  fi
  ok "curl $(curl --version | head -1 | awk '{print $2}')"

  # git
  if ! command -v git &>/dev/null; then
    info "Instalando git..."
    apt-get install -y git &>/dev/null
  fi
  ok "git $(git --version | awk '{print $3}')"

  # Node.js 20
  if command -v node &>/dev/null; then
    local ver major
    ver=$(node --version | sed 's/v//')
    major=$(echo "$ver" | cut -d. -f1)
    if [ "$major" -ge 18 ]; then
      ok "Node.js $ver"
    else
      warn "Node.js $ver desatualizado — instalando v20..."
      curl -fsSL https://deb.nodesource.com/setup_20.x | bash - &>/dev/null
      apt-get install -y nodejs &>/dev/null
      ok "Node.js $(node --version)"
    fi
  else
    info "Instalando Node.js 20..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - &>/dev/null
    apt-get install -y nodejs &>/dev/null
    ok "Node.js $(node --version)"
  fi
  ok "npm $(npm --version)"

  # Nginx
  if ! command -v nginx &>/dev/null; then
    info "Instalando Nginx..."
    apt-get install -y nginx &>/dev/null
  fi
  ok "Nginx instalado"

  # Certbot
  if ! command -v certbot &>/dev/null; then
    info "Instalando Certbot (SSL)..."
    apt-get install -y certbot python3-certbot-nginx &>/dev/null
  fi
  ok "Certbot instalado"

  echo ""
  ok "Todas as dependências prontas!"
}

# ─── PASSO 2 — Credenciais do Supabase ───────────────────────
collect_supabase() {
  step "2" "Configuração do Supabase"

  echo -e "  ${YELLOW}Acesse seu projeto em: https://supabase.com/dashboard${NC}"
  echo -e "  ${YELLOW}As informações abaixo estão em: Settings → API${NC}\n"

  ask "URL do projeto  (ex: https://xxxx.supabase.co)"
  read -r SUPABASE_URL
  while [[ ! "$SUPABASE_URL" =~ ^https://.+\.supabase\.co$ ]]; do
    warn "URL inválida. Deve ser no formato: https://xxxx.supabase.co"
    ask "URL do projeto"
    read -r SUPABASE_URL
  done
  ok "URL: $SUPABASE_URL"

  echo ""
  ask "Anon Key  (começa com 'eyJ...')"
  read -r SUPABASE_ANON_KEY
  while [[ ! "$SUPABASE_ANON_KEY" =~ ^eyJ ]]; do
    warn "Chave inválida. A Anon Key começa com 'eyJ...'"
    ask "Anon Key"
    read -r SUPABASE_ANON_KEY
  done
  ok "Anon Key configurada"

  echo ""
  separator
  echo -e "  ${WHITE}${BOLD}RESUMO${NC}\n"
  echo -e "  URL      : ${CYAN}$SUPABASE_URL${NC}"
  echo -e "  Anon Key : ${CYAN}${SUPABASE_ANON_KEY:0:30}...${NC}"
  echo ""
  ask "Confirmar? (S/n)"
  read -r CONFIRM
  CONFIRM=$(echo "$CONFIRM" | tr '[:upper:]' '[:lower:]')
  if [[ "$CONFIRM" == "n" ]]; then
    warn "Reiniciando configuração..."
    collect_supabase
  fi
}

# ─── PASSO 3 — Domínio e SSL ──────────────────────────────────
collect_domain() {
  step "3" "Configuração do domínio e SSL"

  echo -e "  ${YELLOW}O domínio já deve estar apontando para o IP desta VPS.${NC}\n"

  ask "Domínio  (ex: app.seudominio.com)"
  read -r APP_DOMAIN
  while [ -z "$APP_DOMAIN" ]; do
    warn "Domínio não pode ser vazio."
    ask "Domínio"
    read -r APP_DOMAIN
  done
  ok "Domínio: $APP_DOMAIN"

  echo ""
  ask "E-mail para o certificado SSL (Let's Encrypt)"
  read -r SSL_EMAIL
  while [[ ! "$SSL_EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; do
    warn "E-mail inválido."
    ask "E-mail"
    read -r SSL_EMAIL
  done
  ok "E-mail: $SSL_EMAIL"
}

# ─── PASSO 4 — Criar .env ─────────────────────────────────────
create_env() {
  step "4" "Criando arquivo de configuração (.env)"

  cat > /root/zapd2m/.env << EOF
# zapd2m — gerado pelo instalador automático
VITE_SUPABASE_URL=$SUPABASE_URL
VITE_SUPABASE_PUBLISHABLE_KEY=$SUPABASE_ANON_KEY
EOF

  ok "Arquivo .env criado!"
  info "Suas chaves estão salvas em /root/zapd2m/.env"
}

# ─── PASSO 5 — Instalar dependências do projeto ───────────────
install_project_deps() {
  step "5" "Instalando dependências do projeto (npm install)"

  cd /root/zapd2m

  (npm install --silent 2>&1) &
  spinner $! "Baixando pacotes npm..."

  ok "Dependências instaladas!"
}

# ─── PASSO 6 — Build do frontend ─────────────────────────────
build_frontend() {
  step "6" "Compilando o frontend (npm run build)"

  cd /root/zapd2m

  (npm run build 2>&1) &
  spinner $! "Compilando aplicação React..."

  if [ -d "dist" ]; then
    ok "Build concluído! Pasta dist/ gerada."
  else
    echo -e "\n${RED}✘ Erro no build. Verifique os logs acima.${NC}\n"
    exit 1
  fi
}

# ─── PASSO 7 — Configurar Nginx ───────────────────────────────
configure_nginx() {
  step "7" "Configurando Nginx"

  mkdir -p /var/www/zapd2m
  cp -r /root/zapd2m/dist/. /var/www/zapd2m/

  cat > /etc/nginx/sites-available/zapd2m << EOF
server {
    listen 80;
    server_name $APP_DOMAIN;
    root /var/www/zapd2m;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;
}
EOF

  ln -sf /etc/nginx/sites-available/zapd2m /etc/nginx/sites-enabled/
  rm -f /etc/nginx/sites-enabled/default

  nginx -t &>/dev/null && systemctl reload nginx
  ok "Nginx configurado para $APP_DOMAIN"
}

# ─── PASSO 8 — SSL ────────────────────────────────────────────
configure_ssl() {
  step "8" "Gerando certificado SSL (Let's Encrypt)"

  info "Aguarde, isso pode levar alguns segundos..."

  if certbot --nginx -d "$APP_DOMAIN" \
    --non-interactive --agree-tos \
    -m "$SSL_EMAIL" &>/dev/null; then
    ok "Certificado SSL gerado!"
    ok "HTTPS ativo em: https://$APP_DOMAIN"
  else
    warn "Não foi possível gerar o SSL agora."
    warn "Verifique se o domínio $APP_DOMAIN aponta para este IP."
    info "Para tentar novamente depois: certbot --nginx -d $APP_DOMAIN"
  fi
}

# ─── Resumo final ─────────────────────────────────────────────
print_summary() {
  echo ""
  echo -e "${GREEN}"
  echo "  ╔═══════════════════════════════════════════════════╗"
  echo "  ║      ✅  INSTALAÇÃO CONCLUÍDA COM SUCESSO!        ║"
  echo "  ╚═══════════════════════════════════════════════════╝"
  echo -e "${NC}"
  echo -e "  ${WHITE}${BOLD}Acesse sua aplicação:${NC}"
  echo -e "  ${GREEN}https://$APP_DOMAIN${NC}"
  echo ""
  echo -e "  ${WHITE}${BOLD}PRÓXIMOS PASSOS:${NC}\n"
  echo -e "  ${CYAN}1.${NC} Abra ${WHITE}https://$APP_DOMAIN${NC} no navegador"
  echo -e "  ${CYAN}2.${NC} ${YELLOW}⚠ A primeira conta criada será a conta ADMIN!${NC}"
  echo -e "  ${CYAN}3.${NC} Configure o webhook da Evolution API:"
  echo -e "     ${WHITE}${SUPABASE_URL}/functions/v1/whatsapp-webhook${NC}"
  echo -e "  ${CYAN}4.${NC} No Supabase: Authentication → URL Configuration"
  echo -e "     Site URL: ${WHITE}https://$APP_DOMAIN${NC}"
  echo ""
  echo -e "  ${BLUE}──────────────────────────────────────────────${NC}"
  echo -e "  Dúvidas? Consulte a pasta ${WHITE}/root/zapd2m/guia/${NC}"
  echo ""
}

# ─── Carregar .env existente ─────────────────────────────────
load_existing_env() {
  if [ -f /root/zapd2m/.env ]; then
    source /root/zapd2m/.env
    SUPABASE_URL="${VITE_SUPABASE_URL:-}"
    SUPABASE_ANON_KEY="${VITE_SUPABASE_PUBLISHABLE_KEY:-}"
  fi
  APP_DOMAIN=$(grep -r "server_name" /etc/nginx/sites-available/zapd2m 2>/dev/null | awk '{print $2}' | tr -d ';' | head -1 || echo "")
  SSL_EMAIL=$(grep -r "\-m " /etc/letsencrypt/renewal/*.conf 2>/dev/null | head -1 | awk -F'email = ' '{print $2}' || echo "")
}

# ─── Menu de reparo ───────────────────────────────────────────
repair_menu() {
  print_banner

  load_existing_env

  echo -e "  ${YELLOW}${BOLD}⚠  zapd2m já está instalado nesta VPS!${NC}
"
  echo -e "  ${WHITE}Instalação atual:${NC}"
  [ -n "$APP_DOMAIN" ]      && echo -e "  ${BLUE}•${NC} Domínio   : ${CYAN}$APP_DOMAIN${NC}"    || echo -e "  ${BLUE}•${NC} Domínio   : ${RED}não detectado${NC}"
  [ -n "$SUPABASE_URL" ]    && echo -e "  ${BLUE}•${NC} Supabase  : ${CYAN}$SUPABASE_URL${NC}"  || echo -e "  ${BLUE}•${NC} Supabase  : ${RED}não configurado${NC}"
  echo ""
  echo -e "  ${WHITE}${BOLD}O que deseja fazer?${NC}
"
  echo -e "  ${CYAN}1)${NC} Corrigir o domínio"
  echo -e "  ${CYAN}2)${NC} Atualizar credenciais do Supabase"
  echo -e "  ${CYAN}3)${NC} Atualizar o projeto (git pull + rebuild)"
  echo -e "  ${CYAN}4)${NC} Reinstalar tudo do zero"
  echo -e "  ${CYAN}5)${NC} Cancelar"
  echo ""
  ask "Escolha uma opção (1-5)"
  read -r OPCAO

  case $OPCAO in
    1)
      echo ""
      warn "Domínio atual: ${APP_DOMAIN:-não configurado}"
      collect_domain
      # Garante que as credenciais do Supabase estão carregadas
      if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_ANON_KEY" ]; then
        warn "Credenciais do Supabase não encontradas — precisamos reconfigurá-las."
        collect_supabase
        create_env
      fi
      # Rebuild necessário pois o domínio afeta o .env e o build
      install_project_deps
      build_frontend
      configure_nginx
      configure_ssl
      print_summary
      ;;
    2)
      echo ""
      warn "Supabase atual: ${SUPABASE_URL:-não configurado}"
      collect_supabase
      create_env
      build_frontend
      configure_nginx
      print_summary
      ;;
    3)
      echo ""
      info "Atualizando projeto via git pull..."
      cd /root/zapd2m
      git pull &>/dev/null
      ok "Projeto atualizado!"
      build_frontend
      cp -r /root/zapd2m/dist/. /var/www/zapd2m/
      systemctl reload nginx
      ok "Aplicação atualizada em https://$APP_DOMAIN"
      ;;
    4)
      echo ""
      warn "Isso vai apagar tudo e reinstalar do zero."
      ask "Tem certeza? (s/N)"
      read -r CONFIRM
      CONFIRM=$(echo "$CONFIRM" | tr '[:upper:]' '[:lower:]')
      if [[ "$CONFIRM" == "s" || "$CONFIRM" == "sim" ]]; then
        rm -rf /var/www/zapd2m
        rm -f /etc/nginx/sites-available/zapd2m
        rm -f /etc/nginx/sites-enabled/zapd2m
        install_system_deps
        collect_supabase
        collect_domain
        create_env
        install_project_deps
        build_frontend
        configure_nginx
        configure_ssl
        print_summary
      else
        info "Reinstalação cancelada."
      fi
      ;;
    5)
      info "Operação cancelada."
      exit 0
      ;;
    *)
      warn "Opção inválida. Tente novamente."
      repair_menu
      ;;
  esac
}

# ─── Fluxo principal ──────────────────────────────────────────
main() {
  print_banner

  # Detecta se já existe instalação
  if [ -f /var/www/zapd2m/index.html ] || [ -f /etc/nginx/sites-available/zapd2m ]; then
    repair_menu
    exit 0
  fi

  install_system_deps
  collect_supabase
  collect_domain
  create_env
  install_project_deps
  build_frontend
  configure_nginx
  configure_ssl
  print_summary
}

main
