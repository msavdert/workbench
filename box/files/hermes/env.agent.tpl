# Hermes .env template for the AGENT user's personal gateway (op inject
# renders this to /home/agent/.hermes/.env, mode 600, on every provision).
# This repository is public: secrets AND personal identifiers (Telegram user
# and chat ids) live in 1Password and are referenced here, never inlined.
# Non-secret tool tuning values are plain; they came from the previous
# hermes-vm install (2026-08-26 migration, docs/reference/hermes.md).

TELEGRAM_BOT_TOKEN={{ op://dotfiles/Hermes/telegram-bot-melih }}
TELEGRAM_ALLOWED_USERS={{ op://dotfiles/Hermes/telegram-users-melih }}
TELEGRAM_HOME_CHANNEL={{ op://dotfiles/Hermes/telegram-home-melih }}

HERMES_CUSTOM_API_SYNTHETIC_NEW_API_KEY={{ op://dotfiles/Hermes/synthetic-api-key }}
FIRECRAWL_API_KEY={{ op://dotfiles/Hermes/firecrawl-api-key }}
GITHUB_TOKEN={{ op://dotfiles/GitHub/admintoken }}

TERMINAL_ENV=local
TERMINAL_TIMEOUT=60
BROWSER_SESSION_TIMEOUT=300
BROWSER_INACTIVITY_TIMEOUT=120
