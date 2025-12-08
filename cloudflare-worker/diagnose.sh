#!/bin/bash
# Script de diagnóstico completo para Cloudflare Worker

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║     DIAGNÓSTICO DE INTEGRACIÓN CLOUDFLARE WORKER - WILOBU     ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_ok() {
    echo -e "${GREEN}✓${NC} $1"
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# 1. Verificar Wrangler
echo "[1/7] Verificando Wrangler CLI..."
if command -v wrangler &> /dev/null; then
    VERSION=$(wrangler --version)
    check_ok "Wrangler instalado: $VERSION"
else
    check_fail "Wrangler no instalado. Ejecuta: npm install -g wrangler"
    exit 1
fi
echo ""

# 2. Verificar autenticación
echo "[2/7] Verificando autenticación Cloudflare..."
if wrangler whoami &> /dev/null; then
    check_ok "Sesión activa en Cloudflare"
else
    check_fail "No autenticado. Ejecuta: wrangler login"
    exit 1
fi
echo ""

# 3. Verificar archivos del proyecto
echo "[3/7] Verificando archivos del proyecto..."
FILES=("worker.js" "wrangler.toml" "package.json")
for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        check_ok "$file existe"
    else
        check_fail "$file faltante"
    fi
done
echo ""

# 4. Verificar variables de entorno
echo "[4/7] Verificando configuración..."
if [ -f ".dev.vars" ]; then
    check_ok ".dev.vars configurado"
    
    # Verificar que no estén vacías
    if grep -q "AIza" .dev.vars; then
        check_ok "FIREBASE_API_KEY configurada"
    else
        check_warn "FIREBASE_API_KEY parece vacía"
    fi
else
    check_warn ".dev.vars no existe (solo necesario para desarrollo local)"
fi
echo ""

# 5. Verificar sintaxis del worker
echo "[5/7] Validando sintaxis de worker.js..."
if node -c worker.js 2>/dev/null; then
    check_ok "worker.js sintaxis válida"
else
    check_fail "worker.js tiene errores de sintaxis"
fi
echo ""

# 6. Listar deployments
echo "[6/7] Consultando deployments existentes..."
DEPLOYMENT=$(wrangler deployments list 2>/dev/null | grep -E "Created|Version")
if [ -n "$DEPLOYMENT" ]; then
    check_ok "Worker desplegado previamente"
    echo "$DEPLOYMENT"
else
    check_warn "Sin deployments previos"
fi
echo ""

# 7. Verificar configuración del firmware
echo "[7/7] Verificando configuración en firmware..."
MODEM_PROXY_H="../wilobu_firmware/include/ModemProxy.h"
if [ -f "$MODEM_PROXY_H" ]; then
    PROXY_URL=$(grep 'proxyUrl' "$MODEM_PROXY_H" | cut -d'"' -f2)
    if [ -n "$PROXY_URL" ]; then
        check_ok "URL configurada en firmware: $PROXY_URL"
        
        # Intentar curl para verificar que el worker responde
        echo ""
        echo "Probando conectividad al worker..."
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://$PROXY_URL" -X POST -H "Content-Type: application/json" -d '{}' --max-time 5)
        
        if [ "$HTTP_CODE" = "400" ] || [ "$HTTP_CODE" = "200" ]; then
            check_ok "Worker responde (HTTP $HTTP_CODE)"
        elif [ "$HTTP_CODE" = "000" ]; then
            check_warn "No se pudo conectar al worker (timeout o DNS)"
        else
            check_warn "Worker responde con código: $HTTP_CODE"
        fi
    else
        check_fail "proxyUrl no encontrada en ModemProxy.h"
    fi
else
    check_warn "ModemProxy.h no encontrado (verifica ruta del firmware)"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "RESUMEN:"
echo "  - Si todos los checks son ✓, la integración está lista"
echo "  - Si hay ⚠, revisa los pasos en README.md"
echo "  - Para desplegar: wrangler deploy"
echo "  - Para pruebas locales: npm run dev"
echo "═══════════════════════════════════════════════════════════════"
