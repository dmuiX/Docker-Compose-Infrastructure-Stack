#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Authelia OIDC Client Setup Script
# Adds OIDC clients to Authelia configuration and displays setup info
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

set -e

OIDC_AUTH_METHOD="client_secret_basic"

usage() {
  echo "Usage: ./add-client.sh [--auth-method <method>] <app_name> <redirect_uri> [additional_redirect_uris...]"
  echo ""
  echo "Options:"
  echo "  --auth-method <method>  OIDC token_endpoint_auth_method"
  echo "                          default: client_secret_basic"
  echo "                          allowed: client_secret_basic, client_secret_post, client_secret_jwt, private_key_jwt, none"
  echo "  -h, --help              Show this help"
  echo ""
  echo "Examples:"
  echo "  # Single redirect URI:"
  echo "  ./add-client.sh nextcloud https://nextcloud.domain.org/apps/oidc_login/oidc"
  echo "  ./add-client.sh --auth-method client_secret_post nextcloud https://nextcloud.domain.org/apps/user_oidc/code"
  echo ""
  echo "  # Multiple redirect URIs (for mobile app support):"
  echo "  ./add-client.sh audiobookshelf \\"
  echo "    https://audiobookshelf.domain.org/auth/openid/callback \\"
  echo "    https://audiobookshelf.domain.org/auth/openid/mobile-redirect \\"
  echo "    audiobookshelf://oauth"
  echo ""
  echo "⚠️  Check each app's OIDC docs for the correct callback URL(s)!"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --auth-method)
      if [ -z "$2" ]; then
        echo "❌ Missing value for --auth-method"
        usage
        exit 1
      fi
      OIDC_AUTH_METHOD="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "❌ Unknown option: $1"
      usage
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

case "$OIDC_AUTH_METHOD" in
  client_secret_basic|client_secret_post|client_secret_jwt|private_key_jwt|none)
    ;;
  *)
    echo "❌ Invalid auth method: $OIDC_AUTH_METHOD"
    echo "   Allowed: client_secret_basic, client_secret_post, client_secret_jwt, private_key_jwt, none"
    exit 1
    ;;
esac

APP_NAME="$1"
shift || true
REDIRECT_URIS=("$@")

if [ -z "$APP_NAME" ] || [ ${#REDIRECT_URIS[@]} -eq 0 ]; then
  usage
  exit 1
fi

# Generate client secret using Authelia's crypto tool
echo "Generating client secret..."
CRYPTO_OUTPUT=$(docker run --rm authelia/authelia:latest authelia crypto hash generate pbkdf2 \
  --random --random.length 72 --variant sha512)

# Extract the random password and digest from output
RANDOM_PASSWORD=$(echo "$CRYPTO_OUTPUT" | grep "Random Password:" | cut -d' ' -f3)
CLIENT_SECRET_HASH=$(echo "$CRYPTO_OUTPUT" | grep "Digest:" | cut -d' ' -f2)

CONFIG_PATH="/home/nasadmin/DockerCompose/authelia/config/configuration.yml"

if [ ! -f "$CONFIG_PATH" ]; then
  echo "❌ Config not found at $CONFIG_PATH"
  exit 1
fi

# Check if client already exists - if so, remove it and regenerate
if grep -q "client_id: '${APP_NAME}'" "$CONFIG_PATH" 2>/dev/null || \
   grep -q "client_id: \"${APP_NAME}\"" "$CONFIG_PATH" 2>/dev/null; then

  echo "⚠️  Client '$APP_NAME' already exists - regenerating with new secret..."

  # Remove the full existing client block until the next '- client_id:'
  sudo awk -v app="$APP_NAME" '
    BEGIN { skip = 0 }
    {
      if (skip && $1 == "-" && $2 == "client_id:") {
        skip = 0
      }

      if (!skip && $1 == "-" && $2 == "client_id:") {
        cid = $3
        gsub(/^\047|\047$/, "", cid)
        gsub(/^\"|\"$/, "", cid)
        if (cid == app) {
          skip = 1
          next
        }
      }

      if (!skip) {
        print
      }
    }
  ' "$CONFIG_PATH" > /tmp/authelia_config_clean.yml

  sudo mv /tmp/authelia_config_clean.yml "$CONFIG_PATH"
fi

# Build redirect_uris YAML lines
REDIRECT_URIS_YAML=""
for uri in "${REDIRECT_URIS[@]}"; do
  REDIRECT_URIS_YAML="${REDIRECT_URIS_YAML}
          - '${uri}'"
done

# Create the client YAML block
CLIENT_BLOCK="      - client_id: '${APP_NAME}'
        client_name: '${APP_NAME}'
        client_secret: '${CLIENT_SECRET_HASH}'
        public: false
        authorization_policy: 'two_factor'
        token_endpoint_auth_method: '${OIDC_AUTH_METHOD}'
        redirect_uris:${REDIRECT_URIS_YAML}
        scopes:
          - 'openid'
          - 'profile'
          - 'email'
          - 'groups'
        userinfo_signed_response_alg: 'none'
        response_types:
          - 'code'
        grant_types:
          - 'authorization_code'"

# Append client to config file (after 'clients:' line)
# Using awk for reliable multi-line insertion
sudo awk -v block="$CLIENT_BLOCK" '
  /^[[:space:]]*clients:[[:space:]]*$/ {
    print
    print block
    next
  }
  { print }
' "$CONFIG_PATH" > /tmp/authelia_config_new.yml

sudo mv /tmp/authelia_config_new.yml "$CONFIG_PATH"

echo ""
echo "✅ Added $APP_NAME client to configuration"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 OIDC Configuration for $APP_NAME:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🔐 OpenID Connect Authentication (Top Section):"
echo "✅ Issuer URL:        https://authelia.domain.org"
echo "✅ Discovery endpoint: https://authelia.domain.org/.well-known/openid-configuration"
echo "✅ Authorize URL:     https://authelia.domain.org/api/oidc/authorization"
echo "✅ Token URL:         https://authelia.domain.org/api/oidc/token"
echo "✅ Userinfo URL:      https://authelia.domain.org/api/oidc/userinfo"
echo "✅ JWKS URL:          https://authelia.domain.org/jwks.json"
echo "✅ Logout URL:        (leave empty)"
echo "✅ Client ID:         $APP_NAME"
echo "✅ Client Secret:     $RANDOM_PASSWORD"
echo "✅ Auth Method:       $OIDC_AUTH_METHOD"
echo "✅ Signing Algorithm: RS256"
echo "✅ Redirect URIs:"
for uri in "${REDIRECT_URIS[@]}"; do
  echo "     - $uri"
done
echo ""
echo "👥 User/Group Matching (Bottom Section):"
echo "✅ Match existing users by: Do not match"
echo "✅ Auto Launch:       Off"
echo "✅ Auto Register:     On (creates users on first login)"
echo "✅ Group Claim:       groups"
echo "✅ Advanced Permission Claim: (leave empty)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔄 Restarting Authelia..."
cd /home/nasadmin/DockerCompose/authelia && docker compose -f authelia.yml restart
echo "✅ Authelia restarted! Client is ready to use."
