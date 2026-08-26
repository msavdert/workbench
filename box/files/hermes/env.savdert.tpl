# Hermes .env template for the SAVDERT user's family gateway (op inject
# renders this to /home/savdert/.hermes/.env, mode 600, on every provision).
# The savdert user itself holds no 1Password token; rendering happens during
# provisioning with the agent user's service account. Public repository:
# secrets and personal identifiers are op:// references only.

TELEGRAM_BOT_TOKEN={{ op://dotfiles/Hermes/telegram-bot-savdert }}
TELEGRAM_ALLOWED_USERS={{ op://dotfiles/Hermes/telegram-users-savdert }}
TELEGRAM_HOME_CHANNEL={{ op://dotfiles/Hermes/telegram-home-savdert }}
TELEGRAM_HOME_CHANNEL_NAME={{ op://dotfiles/Hermes/telegram-home-name-savdert }}

HERMES_CUSTOM_API_SYNTHETIC_NEW_API_KEY={{ op://dotfiles/Hermes/synthetic-api-key }}
FIRECRAWL_API_KEY={{ op://dotfiles/Hermes/firecrawl-api-key }}

TERMINAL_ENV=local
TERMINAL_TIMEOUT=60
