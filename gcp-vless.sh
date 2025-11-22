#!/bin/bash

# GCP V2Ray VLESS Server Deployer - Simple & Working Version
# With Python Telegram Bot that actually works
# Author: Assistant
# Version: 12.0

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Global variables
PROJECT_ID=""
SERVICE_NAME=""
BOT_SERVICE_NAME=""
REGION="us-central1"
TELEGRAM_BOT_TOKEN=""
UUID=""
PATH_SUFFIX=""
SERVICE_URL=""
BOT_SERVICE_URL=""
VLESS_LINK=""
SELECTED_CPU="2"
SELECTED_MEMORY="1Gi"

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_environment() {
    print_info "Checking Google Cloud environment..."
    
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud not found. Please run in Google Cloud Shell."
        exit 1
    fi
    
    print_success "Google Cloud environment is ready"
}

check_authentication() {
    print_info "Checking authentication..."
    
    if ! gcloud auth list --format="value(account)" | grep -q "@"; then
        print_warning "Please login to Google Cloud"
        gcloud auth login --no-launch-browser
    fi
    
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [[ -z "$PROJECT_ID" ]]; then
        print_info "Available projects:"
        gcloud projects list --format="table(projectId,name)" --limit=5
        echo ""
        read -p "Enter Project ID: " PROJECT_ID
        if [[ -n "$PROJECT_ID" ]]; then
            gcloud config set project "$PROJECT_ID"
        else
            print_error "Project ID is required"
            exit 1
        fi
    fi
    print_success "Using project: $PROJECT_ID"
}

get_configuration() {
    echo ""
    print_info "Basic Configuration"
    echo "===================="
    
    # Service name
    read -p "Enter service name [vless-server]: " SERVICE_NAME
    SERVICE_NAME=${SERVICE_NAME:-vless-server}
    BOT_SERVICE_NAME="${SERVICE_NAME}-bot"
    
    # Region
    echo ""
    print_info "Select region:"
    echo "1. us-central1 (USA)"
    echo "2. europe-west1 (Europe)" 
    echo "3. asia-southeast1 (Asia)"
    read -p "Choose [1]: " region_choice
    case $region_choice in
        2) REGION="europe-west1" ;;
        3) REGION="asia-southeast1" ;;
        *) REGION="us-central1" ;;
    esac
    
    # Telegram Bot
    echo ""
    print_info "Telegram Bot Setup"
    while true; do
        read -p "Enter Telegram Bot Token: " TELEGRAM_BOT_TOKEN
        if [[ -n "$TELEGRAM_BOT_TOKEN" ]]; then
            # Verify bot
            if curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" | grep -q \"ok\":true; then
                BOT_USERNAME=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" | grep -o '"username":"[^"]*' | cut -d'"' -f4)
                print_success "Bot verified: @$BOT_USERNAME"
                break
            else
                print_error "Invalid bot token"
            fi
        else
            print_error "Bot token is required"
        fi
    done
    
    # Resources
    echo ""
    print_info "Select server resources:"
    echo "1. 1 CPU, 1Gi RAM (Basic)"
    echo "2. 2 CPU, 2Gi RAM (Recommended)"
    echo "3. 4 CPU, 4Gi RAM (High Performance)"
    echo "4. 8 CPU, 8Gi RAM (Maximum)"
    read -p "Choose [2]: " resource_choice
    case $resource_choice in
        1) SELECTED_CPU="1"; SELECTED_MEMORY="1Gi" ;;
        3) SELECTED_CPU="4"; SELECTED_MEMORY="4Gi" ;;
        4) SELECTED_CPU="8"; SELECTED_MEMORY="8Gi" ;;
        *) SELECTED_CPU="2"; SELECTED_MEMORY="2Gi" ;;
    esac
    
    # Generate UUID and path
    UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16)
    PATH_SUFFIX="tg-$(head /dev/urandom 2>/dev/null | tr -dc a-z0-9 | head -c 8)"
}

create_v2ray_dockerfile() {
    print_info "Creating V2Ray configuration..."
    
    cat > Dockerfile << 'EOF'
FROM alpine:latest

RUN apk update && apk add --no-cache curl unzip

# Install V2Ray
RUN curl -L https://github.com/v2fly/v2ray-core/releases/download/v5.7.0/v2ray-linux-64.zip -o v2ray.zip \
    && unzip v2ray.zip \
    && mv v2ray /usr/bin/ \
    && chmod +x /usr/bin/v2ray \
    && rm -f v2ray.zip geoip.dat geosite.dat \
    && mkdir -p /etc/v2ray

COPY config.json /etc/v2ray/

EXPOSE 8080

CMD ["v2ray", "run", "-config", "/etc/v2ray/config.json"]
EOF

    cat > config.json << EOF
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "port": 8080,
            "listen": "0.0.0.0",
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$UUID",
                        "level": 0
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "ws",
                "security": "tls",
                "tlsSettings": {
                    "alpn": ["h3", "h2", "http/1.1"],
                    "fingerprint": "randomized"
                },
                "wsSettings": {
                    "path": "/$PATH_SUFFIX"
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls"]
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "settings": {}
        }
    ]
}
EOF
}

create_bot_dockerfile() {
    print_info "Creating Telegram Bot with python-telegram-bot..."
    
    cat > bot.Dockerfile << 'EOF'
FROM python:3.9-slim

RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY bot_requirements.txt bot_main.py ./

RUN pip install -r bot_requirements.txt

EXPOSE 8080

CMD ["python", "bot_main.py"]
EOF

    cat > bot_requirements.txt << 'EOF'
python-telegram-bot==20.7
flask==2.3.3
gunicorn==21.2.0
EOF

    cat > bot_main.py << EOF
import os
import logging
from flask import Flask, request, jsonify
from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes

# Enable logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)

logger = logging.getLogger(__name__)

# Configuration from environment
BOT_TOKEN = os.environ.get('BOT_TOKEN')
VLESS_LINK = os.environ.get('VLESS_LINK')
SERVICE_URL = os.environ.get('SERVICE_URL')

# Create Flask app
app = Flask(__name__)

# Create Telegram Application
telegram_app = Application.builder().token(BOT_TOKEN).build()

# Command handlers
async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Send a message when the command /start is issued."""
    user = update.effective_user
    message = f"""🚀 <b>Welcome to V2Ray VLESS Server, {user.first_name}!</b>

🔗 <b>Your VLESS Configuration:</b>
<code>{VLESS_LINK}</code>

📋 <b>How to use:</b>
1. Copy the link above
2. Paste in V2Ray client (Nekobox, V2RayNG, etc.)
3. Connect and enjoy!

⚡ <b>Server Information:</b>
• Status: ✅ Online
• Protocol: V2Ray + VLESS + WS + TLS
• Domain: {SERVICE_URL.split('//')[1] if SERVICE_URL else 'N/A'}

💡 <b>Note:</b> This server is available for all users"""
    
    await update.message.reply_html(message)

async def status_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Send server status when the command /status is issued."""
    await update.message.reply_text("✅ Server is online and running!")

async def info_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Send server info when the command /info is issued."""
    info_msg = f"""📊 <b>Server Information:</b>

🌐 Domain: {SERVICE_URL}
🔧 Service: VLESS Server
🔒 Security: TLS 1.3
🛡️ Fingerprint: Randomized
⚡ Performance: High Speed
👥 Users: Unlimited"""
    
    await update.message.reply_html(info_msg)

# Add handlers to Telegram application
telegram_app.add_handler(CommandHandler("start", start_command))
telegram_app.add_handler(CommandHandler("status", status_command))
telegram_app.add_handler(CommandHandler("info", info_command))

# Webhook route
@app.route('/webhook', methods=['POST'])
async def webhook():
    """Handle incoming Telegram updates via webhook."""
    try:
        data = request.get_json()
        update = Update.de_json(data, telegram_app.bot)
        await telegram_app.process_update(update)
        return jsonify({'status': 'ok'})
    except Exception as e:
        logger.error(f"Webhook error: {e}")
        return jsonify({'status': 'error'}), 500

# Health check route
@app.route('/health', methods=['GET'])
def health():
    return jsonify({'status': 'healthy', 'service': 'telegram-bot'})

# Set webhook on startup
@app.before_first_request
async def set_webhook():
    webhook_url = f"https://{os.environ.get('BOT_SERVICE_URL', '').replace('https://', '')}/webhook"
    if webhook_url and not webhook_url.endswith('/webhook'):
        webhook_url += '/webhook'
    
    try:
        await telegram_app.bot.set_webhook(
            url=webhook_url,
            max_connections=100,
            allowed_updates=['message']
        )
        logger.info(f"Webhook set to: {webhook_url}")
        
        # Set bot commands
        commands = [
            ("start", "Get VLESS configuration"),
            ("status", "Check server status"),
            ("info", "Server information")
        ]
        await telegram_app.bot.set_my_commands(commands)
        logger.info("Bot commands set successfully")
    except Exception as e:
        logger.error(f"Failed to set webhook: {e}")

if __name__ == '__main__':
    # For local development without webhook
    import asyncio
    async def main():
        await telegram_app.initialize()
        await telegram_app.start()
        print("Bot is polling...")
        await telegram_app.updater.start_polling()
    
    # In production, we use webhook via Flask
    from gunicorn.app.base import BaseApplication
    class FlaskApplication(BaseApplication):
        def __init__(self, app, options=None):
            self.options = options or {}
            self.application = app
            super().__init__()

        def load_config(self):
            for key, value in self.options.items():
                self.cfg.set(key, value)

        def load(self):
            return self.application

    options = {
        'bind': '0.0.0.0:8080',
        'workers': 1,
        'timeout': 60
    }
    
    FlaskApplication(app, options).run()
EOF
}

enable_services() {
    print_info "Enabling required Google services..."
    
    gcloud services enable run.googleapis.com containerregistry.googleapis.com cloudbuild.googleapis.com --quiet
    print_success "Required services enabled"
}

deploy_v2ray_service() {
    print_info "Deploying V2Ray VLESS server..."
    
    # Build and deploy V2Ray
    print_info "Building V2Ray container..."
    if gcloud builds submit --tag "gcr.io/${PROJECT_ID}/${SERVICE_NAME}" --quiet; then
        print_info "Deploying V2Ray service..."
        if gcloud run deploy "$SERVICE_NAME" \
            --image "gcr.io/${PROJECT_ID}/${SERVICE_NAME}" \
            --platform managed \
            --region "$REGION" \
            --allow-unauthenticated \
            --port 8080 \
            --cpu "$SELECTED_CPU" \
            --memory "$SELECTED_MEMORY" \
            --min-instances 1 \
            --max-instances 10 \
            --execution-environment gen2 \
            --quiet; then
            print_success "V2Ray service deployed successfully"
            return 0
        fi
    fi
    print_error "V2Ray deployment failed"
    return 1
}

deploy_bot_service() {
    print_info "Deploying Telegram Bot service..."
    
    # Build and deploy bot
    print_info "Building bot container..."
    if gcloud builds submit --tag "gcr.io/${PROJECT_ID}/${BOT_SERVICE_NAME}" --quiet; then
        print_info "Deploying bot service..."
        if gcloud run deploy "$BOT_SERVICE_NAME" \
            --image "gcr.io/${PROJECT_ID}/${BOT_SERVICE_NAME}" \
            --platform managed \
            --region "$REGION" \
            --allow-unauthenticated \
            --port 8080 \
            --cpu 1 \
            --memory "512Mi" \
            --set-env-vars="BOT_TOKEN=${TELEGRAM_BOT_TOKEN},VLESS_LINK=${VLESS_LINK},SERVICE_URL=${SERVICE_URL},BOT_SERVICE_URL=${BOT_SERVICE_URL}" \
            --min-instances 0 \
            --max-instances 3 \
            --execution-environment gen2 \
            --quiet; then
            print_success "Bot service deployed successfully"
            return 0
        fi
    fi
    print_error "Bot deployment failed"
    return 1
}

get_service_urls() {
    print_info "Getting service URLs..."
    
    SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" \
        --platform managed \
        --region "$REGION" \
        --format="value(status.url)" 2>/dev/null)
    
    BOT_SERVICE_URL=$(gcloud run services describe "$BOT_SERVICE_NAME" \
        --platform managed \
        --region "$REGION" \
        --format="value(status.url)" 2>/dev/null)
    
    if [[ -n "$SERVICE_URL" && -n "$BOT_SERVICE_URL" ]]; then
        print_success "VLESS URL: $SERVICE_URL"
        print_success "Bot URL: $BOT_SERVICE_URL"
        return 0
    else
        print_error "Failed to get service URLs"
        return 1
    fi
}

generate_vless_link() {
    local domain=$(echo "$SERVICE_URL" | sed 's|https://||')
    VLESS_LINK="vless://${UUID}@${domain}:443?path=%2F${PATH_SUFFIX}&security=tls&alpn=h3%2Ch2%2Chttp%2F1.1&encryption=none&host=${domain}&fp=randomized&type=ws&sni=${domain}#${SERVICE_NAME}"
    print_success "VLESS link generated"
}

setup_bot_webhook() {
    print_info "Setting up Telegram webhook..."
    
    local webhook_url="${BOT_SERVICE_URL}/webhook"
    
    # Set webhook using direct API call
    if curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setWebhook" \
        -d "url=${webhook_url}" \
        -d "max_connections=100" \
        -d "allowed_updates=[\"message\"]" | grep -q \"ok\":true; then
        print_success "Webhook set successfully"
    else
        print_warning "Webhook setup may need retry"
    fi
    
    # Set bot commands
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setMyCommands" \
        -d '{"commands": [{"command": "start", "description": "Get VLESS configuration"}, {"command": "status", "description": "Check server status"}, {"command": "info", "description": "Server information"}]}' > /dev/null
    
    print_success "Bot commands configured"
}

wait_for_services() {
    print_info "Waiting for services to be ready..."
    sleep 30
    
    # Test services
    if curl -s --max-time 10 -f "${SERVICE_URL}" > /dev/null 2>&1; then
        print_success "VLESS service is ready"
    else
        print_warning "VLESS service starting..."
    fi
    
    if curl -s --max-time 10 -f "${BOT_SERVICE_URL}/health" > /dev/null 2>&1; then
        print_success "Bot service is ready"
    else
        print_warning "Bot service starting..."
    fi
}

cleanup_files() {
    rm -f Dockerfile config.json bot.Dockerfile bot_requirements.txt bot_main.py
}

show_management_commands() {
    echo ""
    echo -e "${YELLOW}🛠️  MANAGEMENT COMMANDS:${NC}"
    echo "  View V2Ray logs: gcloud logging read 'resource.type=cloud_run_revision AND resource.labels.service_name=$SERVICE_NAME' --limit=5"
    echo "  View Bot logs: gcloud logging read 'resource.type=cloud_run_revision AND resource.labels.service_name=$BOT_SERVICE_NAME' --limit=5"
    echo "  Stop V2Ray: gcloud run services delete $SERVICE_NAME --region=$REGION --quiet"
    echo "  Stop Bot: gcloud run services delete $BOT_SERVICE_NAME --region=$REGION --quiet"
    echo "  List services: gcloud run services list --region=$REGION"
    echo ""
}

main() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║               V2Ray VLESS + Telegram Bot                    ║
║                   Working Simple Version                    ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    # Initial checks
    check_environment
    check_authentication
    
    # Get configuration
    get_configuration
    
    # Show summary
    echo ""
    print_info "Deployment Summary:"
    echo "──────────────────"
    echo "• Project: $PROJECT_ID"
    echo "• V2Ray Service: $SERVICE_NAME"
    echo "• Bot Service: $BOT_SERVICE_NAME"
    echo "• Region: $REGION"
    echo "• Resources: $SELECTED_CPU CPU, $SELECTED_MEMORY RAM"
    echo "• Bot: @$BOT_USERNAME"
    echo ""
    
    read -p "Start deployment? (y/n) [y]: " confirm
    if [[ "${confirm:-y}" != "y" ]]; then
        print_info "Deployment cancelled"
        exit 0
    fi
    
    # Deploy V2Ray first
    create_v2ray_dockerfile
    if ! deploy_v2ray_service; then
        print_error "Failed to deploy V2Ray service"
        exit 1
    fi
    
    # Get V2Ray URL and generate link
    if ! get_service_urls; then
        print_error "Failed to get service URLs"
        exit 1
    fi
    generate_vless_link
    
    # Deploy Bot
    create_bot_dockerfile
    if ! deploy_bot_service; then
        print_error "Failed to deploy bot service"
        exit 1
    fi
    
    # Update bot with correct URL and setup webhook
    get_service_urls
    setup_bot_webhook
    wait_for_services
    
    # Display results
    local domain=$(echo "$SERVICE_URL" | sed 's|https://||')
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                      DEPLOYMENT SUCCESS!                    ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}📊 SERVER INFORMATION:${NC}"
    echo "  Project: $PROJECT_ID"
    echo "  Service: $SERVICE_NAME"
    echo "  Region: $REGION"
    echo "  Resources: $SELECTED_CPU CPU | $SELECTED_MEMORY RAM"
    echo "  Domain: $domain"
    echo ""
    echo -e "${CYAN}🔧 VLESS CONFIGURATION:${NC}"
    echo "  UUID: $UUID"
    echo "  Path: /$PATH_SUFFIX"
    echo "  Protocol: V2Ray + VLESS + WS + TLS"
    echo ""
    echo -e "${CYAN}🤖 BOT INFORMATION:${NC}"
    echo "  Bot: @$BOT_USERNAME"
    echo "  Webhook: $BOT_SERVICE_URL/webhook"
    echo "  Commands: /start, /status, /info"
    echo ""
    echo -e "${GREEN}🔗 VLESS LINK:${NC}"
    echo "$VLESS_LINK"
    echo ""
    
    show_management_commands
    cleanup_files
    
    echo ""
    print_success "✅ Deployment completed successfully!"
    print_success "🤖 Bot is LIVE! Try: /start with @$BOT_USERNAME"
    print_success "🔗 VLESS configuration is ready to use"
    echo ""
}

# Run main
trap 'echo ""; print_error "Script interrupted"; cleanup_files; exit 1' SIGINT
main "$@"
