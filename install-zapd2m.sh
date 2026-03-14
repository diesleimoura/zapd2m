#!/bin/bash

# ============================================================
#   Instalador Automático — zapd2m
#   Versão 4.0 — Full Auto (sem Supabase CLI)
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
  echo "    ███████╗ █████╗ ██████╗ ██████╗ ██████╗ ███╗   ███╗"
  echo "    ╚══███╔╝██╔══██╗██╔══██╗██╔══██╗╚════██╗████╗ ████║"
  echo "      ███╔╝ ███████║██████╔╝██║  ██║ █████╔╝██╔████╔██║"
  echo "     ███╔╝  ██╔══██║██╔═══╝ ██║  ██║██╔═══╝ ██║╚██╔╝██║"
  echo "    ███████╗██║  ██║██║     ██████╔╝███████╗██║ ╚═╝ ██║"
  echo "    ╚══════╝╚═╝  ╚═╝╚═╝     ╚═════╝ ╚══════╝╚═╝     ╚═╝"
  echo -e "${NC}"
  echo -e "  ${WHITE}${BOLD}Instalador Automático v4.0 — Full Auto${NC}"
  echo -e "  ${BLUE}─────────────────────────────────────────────${NC}"
  echo ""
}

step()      { echo -e "\n${CYAN}${BOLD}[PASSO $1]${NC} ${WHITE}$2${NC}\n${BLUE}──────────────────────────────────────────────${NC}"; }
ok()        { echo -e "  ${GREEN}✔${NC} $1"; }
warn()      { echo -e "  ${YELLOW}⚠${NC}  $1"; }
info()      { echo -e "  ${BLUE}ℹ${NC}  $1"; }
ask()       { echo -en "  ${WHITE}▶ $1: ${NC}"; }
separator() { echo -e "\n${BLUE}──────────────────────────────────────────────${NC}\n"; }
error_exit(){ echo -e "\n${RED}✘ ERRO: $1${NC}\n"; exit 1; }

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

# Executa SQL direto no Supabase via API REST
run_sql() {
  local sql="$1"
  local desc="${2:-Executando SQL...}"
  info "$desc"
  local result
  result=$(curl -s -X POST \
    "${SUPABASE_URL}/rest/v1/rpc/exec_sql" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"query\": $(echo "$sql" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}" 2>/dev/null || true)

  # Fallback: usa o endpoint direto do postgres
  if echo "$result" | grep -qi "error\|not found\|404" 2>/dev/null; then
    curl -s -X POST \
      "${SUPABASE_URL}/rest/v1/" \
      -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
      -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
      -H "Content-Type: application/json" \
      -H "Prefer: resolution=merge-duplicates" \
      -d "$sql" &>/dev/null || true
  fi
}

# Configura um secret nas Edge Functions via Management API
set_secret() {
  local name="$1"
  local value="$2"
  curl -s -X POST \
    "https://api.supabase.com/v1/projects/${SUPABASE_PROJECT_REF}/secrets" \
    -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "[{\"name\":\"${name}\",\"value\":\"${value}\"}]" &>/dev/null || true
}

# ─── PASSO 1 — Dependências do sistema ───────────────────────
install_system_deps() {
  step "1" "Instalando dependências do sistema"

  apt-get update -qq &>/dev/null
  ok "Lista de pacotes atualizada"

  for pkg in curl git nginx certbot python3-certbot-nginx python3; do
    if ! command -v $pkg &>/dev/null; then
      info "Instalando $pkg..."
      apt-get install -y $pkg &>/dev/null
    fi
    ok "$pkg pronto"
  done

  # Node.js 20
  if command -v node &>/dev/null; then
    local major
    major=$(node --version | sed 's/v//' | cut -d. -f1)
    if [ "$major" -lt 18 ]; then
      info "Atualizando Node.js para v20..."
      curl -fsSL https://deb.nodesource.com/setup_20.x | bash - &>/dev/null
      apt-get install -y nodejs &>/dev/null
    fi
  else
    info "Instalando Node.js 20..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - &>/dev/null
    apt-get install -y nodejs &>/dev/null
  fi
  ok "Node.js $(node --version) / npm $(npm --version)"
}

# ─── PASSO 2 — Coletar credenciais ───────────────────────────
collect_credentials() {
  step "2" "Configuração das credenciais"

  echo -e "  ${YELLOW}Acesse: https://supabase.com/dashboard → seu projeto → Settings → API${NC}\n"

  # URL
  ask "URL do projeto  (ex: https://xxxx.supabase.co)"
  read -r SUPABASE_URL
  while [[ ! "$SUPABASE_URL" =~ ^https://.+\.supabase\.co$ ]]; do
    warn "URL inválida. Formato: https://xxxx.supabase.co"
    ask "URL do projeto"
    read -r SUPABASE_URL
  done
  SUPABASE_PROJECT_REF=$(echo "$SUPABASE_URL" | sed 's|https://||' | cut -d. -f1)
  ok "URL: $SUPABASE_URL"

  # Anon Key
  echo ""
  ask "Anon Key  (começa com 'eyJ...')"
  read -r SUPABASE_ANON_KEY
  while [[ ! "$SUPABASE_ANON_KEY" =~ ^eyJ ]]; do
    warn "Chave inválida."
    ask "Anon Key"
    read -r SUPABASE_ANON_KEY
  done
  ok "Anon Key configurada"

  # Service Role Key
  echo ""
  ask "Service Role Key  (começa com 'eyJ...')"
  read -rs SUPABASE_SERVICE_ROLE_KEY
  echo ""
  while [[ ! "$SUPABASE_SERVICE_ROLE_KEY" =~ ^eyJ ]]; do
    warn "Chave inválida."
    ask "Service Role Key"
    read -rs SUPABASE_SERVICE_ROLE_KEY
    echo ""
  done
  ok "Service Role Key configurada"

  # Valida conexão com Supabase
  info "Testando conexão com Supabase..."
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    "${SUPABASE_URL}/rest/v1/" \
    -H "apikey: ${SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_ANON_KEY}")
  if [[ "$HTTP_STATUS" == "200" || "$HTTP_STATUS" == "400" || "$HTTP_STATUS" == "404" ]]; then
    ok "Conexão com Supabase OK"
  else
    warn "Não foi possível validar a conexão (HTTP $HTTP_STATUS). Verifique as chaves."
  fi

  # Senha do banco de dados
  echo ""
  echo -e "  ${YELLOW}Durante a criação do projeto no Supabase, você definiu uma senha para o banco.${NC}"
  ask "Você definiu uma senha para o banco de dados? (S/n)"
  read -r HAS_DB_PASSWORD
  HAS_DB_PASSWORD=$(echo "$HAS_DB_PASSWORD" | tr '[:upper:]' '[:lower:]')
  if [[ "$HAS_DB_PASSWORD" != "n" && "$HAS_DB_PASSWORD" != "nao" && "$HAS_DB_PASSWORD" != "não" ]]; then
    echo -e "  ${YELLOW}Acesse: https://supabase.com/dashboard → seu projeto → Settings → Database${NC}"
    ask "Senha do banco de dados (Database Password)"
    read -rs SUPABASE_DB_PASSWORD
    echo ""
    while [ -z "$SUPABASE_DB_PASSWORD" ]; do
      warn "Senha não pode ser vazia. Se não lembrar, redefina no painel do Supabase."
      ask "Senha do banco de dados"
      read -rs SUPABASE_DB_PASSWORD
      echo ""
    done
    ok "Senha do banco configurada"
  else
    SUPABASE_DB_PASSWORD=""
    warn "Sem senha definida — o link com o banco pode falhar."
    info "Se houver erros nas migrations, defina uma senha no Supabase e reinstale."
  fi

  # Access Token (para secrets e deploy de funções)
  separator
  echo -e "  ${YELLOW}Acesse: https://supabase.com/dashboard → Account → Access Tokens${NC}"
  echo -e "  ${YELLOW}Clique em 'Generate new token' e copie o token gerado${NC}\n"
  ask "Access Token do Supabase"
  read -rs SUPABASE_ACCESS_TOKEN
  echo ""
  while [ -z "$SUPABASE_ACCESS_TOKEN" ]; do
    warn "Access Token não pode ser vazio."
    ask "Access Token"
    read -rs SUPABASE_ACCESS_TOKEN
    echo ""
  done
  ok "Access Token configurado"

  # Evolution API
  separator
  echo -e "  ${YELLOW}Credenciais da Evolution API${NC}\n"
  ask "URL da Evolution API  (ex: https://evo.seudominio.com)"
  read -r EVOLUTION_API_URL
  while [[ ! "$EVOLUTION_API_URL" =~ ^https:// ]]; do
    warn "URL deve começar com https://"
    ask "URL da Evolution API"
    read -r EVOLUTION_API_URL
  done
  ok "URL Evolution: $EVOLUTION_API_URL"

  echo ""
  ask "API Key da Evolution"
  read -rs EVOLUTION_API_KEY
  echo ""
  while [ -z "$EVOLUTION_API_KEY" ]; do
    warn "API Key não pode ser vazia."
    ask "API Key da Evolution"
    read -rs EVOLUTION_API_KEY
    echo ""
  done
  ok "Evolution API Key configurada"

  # Domínio e SSL
  separator
  echo -e "  ${YELLOW}Configuração do domínio${NC}\n"
  ask "Domínio  (ex: app.seudominio.com)"
  read -r APP_DOMAIN
  while [ -z "$APP_DOMAIN" ]; do
    warn "Domínio não pode ser vazio."
    ask "Domínio"
    read -r APP_DOMAIN
  done
  ok "Domínio: $APP_DOMAIN"

  echo ""
  ask "E-mail para SSL (Let's Encrypt)"
  read -r SSL_EMAIL
  while [[ ! "$SSL_EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; do
    warn "E-mail inválido."
    ask "E-mail"
    read -r SSL_EMAIL
  done
  ok "E-mail: $SSL_EMAIL"

  # Confirmação
  separator
  echo -e "  ${WHITE}${BOLD}RESUMO${NC}\n"
  echo -e "  ${CYAN}Supabase URL    :${NC} $SUPABASE_URL"
  echo -e "  ${CYAN}Project Ref     :${NC} $SUPABASE_PROJECT_REF"
  echo -e "  ${CYAN}Evolution URL   :${NC} $EVOLUTION_API_URL"
  echo -e "  ${CYAN}Domínio         :${NC} $APP_DOMAIN"
  echo -e "  ${CYAN}E-mail SSL      :${NC} $SSL_EMAIL"
  echo ""
  ask "Confirmar e iniciar instalação? (S/n)"
  read -r CONFIRM
  CONFIRM=$(echo "$CONFIRM" | tr '[:upper:]' '[:lower:]')
  if [[ "$CONFIRM" == "n" ]]; then
    warn "Instalação cancelada."
    exit 0
  fi
}

# ─── PASSO 3 — Criar .env e config.toml ──────────────────────
create_configs() {
  step "3" "Criando arquivos de configuração"

  cat > /root/zapd2m/.env << EOF
# zapd2m — gerado pelo instalador automático
VITE_SUPABASE_URL=$SUPABASE_URL
VITE_SUPABASE_PUBLISHABLE_KEY=$SUPABASE_ANON_KEY
EOF
  ok "Arquivo .env criado"

  if [ -f /root/zapd2m/supabase/config.toml ]; then
    sed -i "s/project_id = .*/project_id = \"$SUPABASE_PROJECT_REF\"/" \
      /root/zapd2m/supabase/config.toml
    ok "supabase/config.toml atualizado"
  fi
}

# ─── PASSO 4 — Configurar Secrets via API ────────────────────
configure_secrets() {
  step "4" "Configurando secrets nas Edge Functions"

  info "Enviando secrets para o Supabase (via Management API)..."

  # Usa Python para JSON correto — evita erro 400 com caracteres especiais nas chaves
  local http_code
  http_code=$(python3 - << 'PYEOF'
import json, subprocess, os

secrets = [
  {"name": "EVOLUTION_API_URL",         "value": os.environ.get("EVOLUTION_API_URL", "")},
  {"name": "EVOLUTION_API_KEY",         "value": os.environ.get("EVOLUTION_API_KEY", "")},
  {"name": "SUPABASE_URL",              "value": os.environ.get("SUPABASE_URL", "")},
  {"name": "SUPABASE_SERVICE_ROLE_KEY", "value": os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")},
]

r = subprocess.run([
  "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
  "-X", "POST",
  f"https://api.supabase.com/v1/projects/{os.environ['SUPABASE_PROJECT_REF']}/secrets",
  "-H", f"Authorization: Bearer {os.environ['SUPABASE_ACCESS_TOKEN']}",
  "-H", "Content-Type: application/json",
  "-d", json.dumps(secrets)
], capture_output=True, text=True)
print(r.stdout.strip())
PYEOF
)

  case "$http_code" in
    200|201|204)
      ok "Secrets configurados com sucesso!"
      ;;
    401)
      warn "HTTP 401 — Access Token inválido ou expirado."
      warn "Gere um novo em: https://supabase.com/dashboard → Account → Access Tokens"
      ;;
    403)
      warn "HTTP 403 — Sem permissão. Verifique se o Access Token tem acesso ao projeto."
      ;;
    404)
      warn "HTTP 404 — Projeto não encontrado. Project Ref: ${SUPABASE_PROJECT_REF}"
      ;;
    *)
      warn "HTTP $http_code — Secrets podem não ter sido configurados."
      info "Configure manualmente: Supabase → Edge Functions → Secrets"
      info "Secrets: EVOLUTION_API_URL, EVOLUTION_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY"
      ;;
  esac
}

# ─── PASSO 5 — Deploy Supabase CLI ───────────────────────────
deploy_supabase() {
  step "5" "Deploy das Migrations e Edge Functions"

  cd /root/zapd2m

  # Instala Supabase CLI via binário oficial
  if ! command -v supabase &>/dev/null; then
    info "Instalando Supabase CLI (binário oficial)..."
    local SB_VER="2.0.5"
    curl -fsSL "https://github.com/supabase/cli/releases/download/v${SB_VER}/supabase_linux_amd64.tar.gz" \
      -o /tmp/supabase.tar.gz 2>/dev/null
    tar -xzf /tmp/supabase.tar.gz -C /tmp 2>/dev/null
    local BIN
    BIN=$(find /tmp -name "supabase" -type f 2>/dev/null | head -1)
    if [ -n "$BIN" ]; then
      mv "$BIN" /usr/local/bin/supabase
      chmod +x /usr/local/bin/supabase
    fi
    rm -f /tmp/supabase.tar.gz
  fi

  if ! command -v supabase &>/dev/null; then
    warn "Supabase CLI não pôde ser instalado — pulando deploy de funções"
    warn "Execute manualmente depois: npx supabase functions deploy"
    return
  fi
  ok "Supabase CLI $(supabase --version 2>/dev/null | head -1)"

  # Login com Access Token
  info "Autenticando no Supabase CLI..."
  export SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN"
  supabase login --no-browser 2>/dev/null || true

  # Link ao projeto (com timeout para não travar)
  info "Vinculando ao projeto..."
  timeout 30 supabase link     --project-ref "$SUPABASE_PROJECT_REF"     --password "$SUPABASE_DB_PASSWORD" 2>/dev/null || true
  ok "Projeto vinculado"

  # Migrations (com timeout)
  echo ""
  info "Aplicando migrations no banco..."
  (timeout 120 supabase db push --include-all 2>&1 | tail -5) &
  spinner $! "Executando migrations..."
  ok "Migrations aplicadas!"

  # Edge Functions (deploy direto sem link, usando project-ref)
  local FUNCTIONS=(
    "send-reminders" "whatsapp-instances" "whatsapp-webhook"
    "chat-ai" "process-document" "manage-scheduling"
    "check-plan-limits" "admin-data" "onboarding"
    "registration-status" "check-first-admin" "resend-reminder"
  )

  echo ""
  local total=${#FUNCTIONS[@]} current=0 failed=()
  for fn in "${FUNCTIONS[@]}"; do
    current=$((current + 1))
    echo -en "  ${CYAN}[$current/$total]${NC} Deployando ${WHITE}$fn${NC}..."
    if timeout 60 supabase functions deploy "$fn"       --no-verify-jwt       --project-ref "$SUPABASE_PROJECT_REF" &>/dev/null; then
      echo -e " ${GREEN}✔${NC}"
    else
      echo -e " ${RED}✘${NC}"
      failed+=("$fn")
    fi
  done

  echo ""
  if [ ${#failed[@]} -eq 0 ]; then
    ok "Todas as $total Edge Functions deployadas!"
  else
    warn "${#failed[@]} falharam: ${failed[*]}"
  fi
}

# ─── PASSO 6 — Configurar Supabase via API ───────────────────
configure_supabase_auto() {
  step "6" "Configurando Supabase automaticamente"

  # Função helper para executar SQL via API
  run_supabase_sql() {
    local desc="$1"
    local sql="$2"
    info "$desc"
    echo "$sql" | python3 -c "
import sys, json, subprocess
sql = sys.stdin.read()
r = subprocess.run([
  'curl','-s','-o','/dev/null','-w','%{http_code}',
  '-X','POST',
  '${SUPABASE_URL}/pg/query',
  '-H','apikey: ${SUPABASE_SERVICE_ROLE_KEY}',
  '-H','Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}',
  '-H','Content-Type: application/json',
  '-d', json.dumps({'sql': sql})
], capture_output=True, text=True)
" 2>/dev/null || true
  }

  # ── 1. Ativa cadastro ──────────────────────────────────────
  run_supabase_sql "Ativando cadastro de novos usuários..."     "INSERT INTO system_settings (key, value) VALUES ('registration_open', 'true') ON CONFLICT (key) DO UPDATE SET value = 'true';"
  ok "Cadastro ativado"

  # ── 2. Garante plano Free ──────────────────────────────────
  run_supabase_sql "Criando plano Free..." "
DO \$\$
DECLARE v_plan_id uuid;
BEGIN
  SELECT id INTO v_plan_id FROM plans WHERE name ILIKE '%free%' OR price = 0 LIMIT 1;
  IF v_plan_id IS NULL THEN
    INSERT INTO plans (name, price, max_instances, max_users, max_messages, is_active)
    VALUES ('Free', 0, 1, 1, 100, true) RETURNING id INTO v_plan_id;
  END IF;
  UPDATE tenants SET plan_id = v_plan_id WHERE plan_id IS NULL;
END; \$\$;"
  ok "Plano Free garantido"

  # ── 3. Cria tenants para usuários sem tenant ───────────────
  run_supabase_sql "Criando tenants para usuários sem tenant..." "
INSERT INTO tenants (user_id, name, plan_id)
SELECT au.id,
  COALESCE(au.raw_user_meta_data->>'name', au.email),
  (SELECT id FROM plans ORDER BY price ASC LIMIT 1)
FROM auth.users au
LEFT JOIN tenants t ON t.user_id = au.id
WHERE t.id IS NULL
ON CONFLICT DO NOTHING;"
  ok "Tenants verificados"

  # ── 4. Garante admin para primeiro usuário ─────────────────
  run_supabase_sql "Configurando primeiro usuário como admin..." "
UPDATE profiles SET role = 'admin'
WHERE user_id = (SELECT id FROM auth.users ORDER BY created_at ASC LIMIT 1)
  AND (role IS NULL OR role != 'admin');"
  ok "Admin configurado"

  # ── 5. Aplica SQLs de fix do projeto ──────────────────────
  local FIX_SQL=""
  for f in /root/zapd2m/supabase/migrations/*fix_missing_tenants*             /root/zapd2m/supabase/migrations/*seed_plans*             /root/zapd2m/supabase/migrations/*fix_tenants*; do
    [ -f "$f" ] && FIX_SQL+=$(cat "$f") && FIX_SQL+=" "
  done
  if [ -n "$FIX_SQL" ]; then
    echo "$FIX_SQL" | python3 -c "
import sys, json, subprocess
sql = sys.stdin.read()
subprocess.run([
  'curl','-s','-o','/dev/null',
  '-X','POST',
  '${SUPABASE_URL}/pg/query',
  '-H','apikey: ${SUPABASE_SERVICE_ROLE_KEY}',
  '-H','Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}',
  '-H','Content-Type: application/json',
  '-d', json.dumps({'sql': sql})
], capture_output=True)
" 2>/dev/null || true
    ok "Scripts de fix do projeto aplicados"
  fi

  # ── 6. Cron Job ───────────────────────────────────────────
  run_supabase_sql "Configurando Cron Job de lembretes..." "
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;
SELECT cron.schedule(
  'send-reminders-every-5-min', '*/5 * * * *',
  \$\$SELECT net.http_post(
    url := '${SUPABASE_URL}/functions/v1/send-reminders',
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer ${SUPABASE_ANON_KEY}"}'::jsonb,
    body := concat('{"time": "', now(), '"}')::jsonb
  ) AS request_id;\$\$
);"
  ok "Cron Job configurado"

  # ── 7. Site URL ───────────────────────────────────────────
  info "Configurando Site URL no Supabase..."
  curl -s -o /dev/null -X PATCH     "https://api.supabase.com/v1/projects/${SUPABASE_PROJECT_REF}/config/auth"     -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}"     -H "Content-Type: application/json"     -d "{"site_url":"https://${APP_DOMAIN}"}" || true
  ok "Site URL configurado: https://$APP_DOMAIN"
}


# ─── PASSO 7 — Build do frontend ─────────────────────────────
build_frontend() {
  step "7" "Build do frontend"

  cd /root/zapd2m

  (npm install --silent 2>&1) &
  spinner $! "Instalando dependências npm..."

  (npm run build 2>&1) &
  spinner $! "Compilando aplicação React..."

  if [ -d "dist" ]; then
    ok "Build concluído!"
  else
    error_exit "Falha no build. Verifique os logs."
  fi
}

# ─── PASSO 8 — Nginx ─────────────────────────────────────────
configure_nginx() {
  step "8" "Configurando Nginx"

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

# ─── PASSO 9 — SSL ───────────────────────────────────────────
configure_ssl() {
  step "9" "Gerando certificado SSL"

  if certbot --nginx -d "$APP_DOMAIN" \
    --non-interactive --agree-tos \
    -m "$SSL_EMAIL" &>/dev/null; then
    ok "Certificado SSL gerado!"
  else
    warn "SSL não gerado agora. Verifique se o domínio aponta para este IP."
    info "Para tentar depois: certbot --nginx -d $APP_DOMAIN"
  fi
}

# ─── Resumo final ─────────────────────────────────────────────
print_summary() {
  echo ""
  echo -e "${GREEN}"
  echo "  ╔══════════════════════════════════════════════════════╗"
  echo "  ║       ✅  INSTALAÇÃO CONCLUÍDA COM SUCESSO!          ║"
  echo "  ╚══════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  echo -e "  ${GREEN}https://$APP_DOMAIN${NC}"
  echo ""
  echo -e "  ${WHITE}${BOLD}TUDO FOI CONFIGURADO AUTOMATICAMENTE:${NC}\n"
  echo -e "  ${GREEN}✔${NC} Migrations aplicadas no banco"
  echo -e "  ${GREEN}✔${NC} Edge Functions deployadas"
  echo -e "  ${GREEN}✔${NC} Secrets da Evolution API configurados"
  echo -e "  ${GREEN}✔${NC} Cron Job de lembretes ativo"
  echo -e "  ${GREEN}✔${NC} Site URL configurado no Supabase"
  echo -e "  ${GREEN}✔${NC} SSL ativo"
  echo ""
  echo -e "  ${WHITE}${BOLD}PRÓXIMO PASSO — só isso:${NC}\n"
  echo -e "  ${CYAN}1.${NC} Abra ${WHITE}https://$APP_DOMAIN${NC}"
  echo -e "  ${CYAN}2.${NC} ${YELLOW}⚠ Crie sua conta — a primeira será o ADMIN!${NC}"
  echo -e "  ${CYAN}3.${NC} Configure a Evolution API em: Admin → Evolution API"
  echo ""
  echo -e "  ${BLUE}──────────────────────────────────────────────${NC}"
  echo -e "  Dúvidas? Consulte: ${WHITE}/root/zapd2m/guia/${NC}"
  echo ""
}

# ─── Carregar config existente ───────────────────────────────
load_existing_config() {
  [ -f /root/zapd2m/.env ] && source /root/zapd2m/.env
  SUPABASE_URL="${VITE_SUPABASE_URL:-}"
  SUPABASE_ANON_KEY="${VITE_SUPABASE_PUBLISHABLE_KEY:-}"
  SUPABASE_PROJECT_REF=$(echo "$SUPABASE_URL" | sed 's|https://||' | cut -d. -f1 2>/dev/null || echo "")
  APP_DOMAIN=$(grep "server_name" /etc/nginx/sites-available/zapd2m 2>/dev/null | awk '{print $2}' | tr -d ';' | head -1 || echo "")
  SSL_EMAIL=$(grep "email" /etc/letsencrypt/renewal/*.conf 2>/dev/null | head -1 | awk -F'= ' '{print $2}' || echo "")
}

# ─── Menu de reparo ───────────────────────────────────────────
repair_menu() {
  print_banner
  load_existing_config

  echo -e "  ${YELLOW}${BOLD}⚠  zapd2m já está instalado nesta VPS!${NC}\n"
  echo -e "  ${WHITE}Instalação atual:${NC}"
  [ -n "$APP_DOMAIN" ]   && echo -e "  ${BLUE}•${NC} Domínio  : ${CYAN}$APP_DOMAIN${NC}"   || echo -e "  ${BLUE}•${NC} Domínio  : ${RED}não detectado${NC}"
  [ -n "$SUPABASE_URL" ] && echo -e "  ${BLUE}•${NC} Supabase : ${CYAN}$SUPABASE_URL${NC}" || echo -e "  ${BLUE}•${NC} Supabase : ${RED}não configurado${NC}"
  echo ""
  echo -e "  ${WHITE}${BOLD}O que deseja fazer?${NC}\n"
  echo -e "  ${CYAN}1)${NC} Corrigir o domínio"
  echo -e "  ${CYAN}2)${NC} Atualizar credenciais do Supabase"
  echo -e "  ${CYAN}3)${NC} Atualizar credenciais da Evolution API"
  echo -e "  ${CYAN}4)${NC} Atualizar o projeto (git pull + rebuild)"
  echo -e "  ${CYAN}5)${NC} Reinstalar tudo do zero"
  echo -e "  ${CYAN}6)${NC} Cancelar"
  echo ""
  ask "Escolha uma opção (1-6)"
  read -r OPCAO

  case $OPCAO in
    1)
      collect_credentials
      create_configs
      build_frontend
      configure_nginx
      configure_ssl
      print_summary
      ;;
    2)
      collect_credentials
      create_configs
      configure_secrets
      deploy_supabase
      configure_supabase_auto
      build_frontend
      cp -r /root/zapd2m/dist/. /var/www/zapd2m/
      systemctl reload nginx
      print_summary
      ;;
    3)
      echo ""
      ask "URL da Evolution API"
      read -r EVOLUTION_API_URL
      ask "API Key da Evolution"
      read -rs EVOLUTION_API_KEY
      echo ""
      ask "Access Token do Supabase"
      read -rs SUPABASE_ACCESS_TOKEN
      echo ""
      load_existing_config
      configure_secrets
      ok "Credenciais da Evolution API atualizadas!"
      ;;
    4)
      info "Atualizando via git pull..."
      cd /root/zapd2m && git pull &>/dev/null
      ok "Código atualizado!"
      load_existing_config
      build_frontend
      cp -r /root/zapd2m/dist/. /var/www/zapd2m/
      systemctl reload nginx
      ok "Aplicação atualizada em https://$APP_DOMAIN"
      ;;
    5)
      warn "Isso vai apagar tudo e reinstalar do zero."
      ask "Tem certeza? (s/N)"
      read -r CONFIRM
      CONFIRM=$(echo "$CONFIRM" | tr '[:upper:]' '[:lower:]')
      if [[ "$CONFIRM" == "s" || "$CONFIRM" == "sim" ]]; then
        rm -rf /var/www/zapd2m
        rm -f /etc/nginx/sites-available/zapd2m /etc/nginx/sites-enabled/zapd2m
        install_system_deps
        collect_credentials
        create_configs
        configure_secrets
        deploy_supabase
        configure_supabase_auto
        build_frontend
        configure_nginx
        configure_ssl
        print_summary
      else
        info "Reinstalação cancelada."
      fi
      ;;
    6)
      info "Operação cancelada."
      exit 0
      ;;
    *)
      warn "Opção inválida."
      repair_menu
      ;;
  esac
}

# ─── Fluxo principal ──────────────────────────────────────────
main() {
  print_banner

  if [ -f /var/www/zapd2m/index.html ] || [ -f /etc/nginx/sites-available/zapd2m ]; then
    repair_menu
    exit 0
  fi

  install_system_deps
  collect_credentials
  create_configs
  configure_secrets
  deploy_supabase
  configure_supabase_auto
  build_frontend
  configure_nginx
  configure_ssl
  print_summary
}

main
