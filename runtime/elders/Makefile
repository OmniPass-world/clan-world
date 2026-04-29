# ClanWorld Elders harness — Makefile
#
# Source tree: runtime/elders/ in the clan-world repo
# Installed at: ~/clan-world/ (or DEST)
#
# Two modes:
#   From source tree:   make install [DEST=~/clan-world]   — materialize runtime
#   From installed dir: make elders-up / ttyd-up / etc.    — operate the cluster
#
# Usage:
#   make install [DEST=~/clan-world]  Materialize runtime from source (idempotent)
#   make setup            Ensure dirs + ttyd unit files exist (alias for install)
#   make elders-up        Start all 4 Elder tmux sessions
#   make elders-down      Kill all 4 Elder tmux sessions
#   make elders-status    Show which sessions are alive
#   make elder-N          Start one Elder (N = 1..4)
#   make elders-greet     Inject /clear + /rename + /color into all 4 REPLs
#   make elder-greet-N    Inject startup commands into one Elder
#   make ttyd-up          Start all 4 ttyd readonly web services
#   make ttyd-down        Stop all 4 ttyd services
#   make ttyd-status      Show ttyd service state
#   make seed-liquidity   (stub) Seed Unicorn Town liquidity pool
#   make help             Show this list
#
# Pair with aliases.sh for shell shortcuts (`elder-1`, `elders-up`, etc).

REPO_DIR     := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
ELDER_DIR    := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
DEST         ?= $(HOME)/clan-world
ELDER_NUMBERS := 1 2 3 4
SYSTEMD_USER_DIR := $(HOME)/.config/systemd/user

.PHONY: help install setup elders-up elders-down elders-status \
        ttyd-up ttyd-down ttyd-status ttyd-units \
        seed-liquidity elders-greet \
        $(addprefix elder-,$(ELDER_NUMBERS)) \
        $(addprefix elder-greet-,$(ELDER_NUMBERS))

help:
	@echo "ClanWorld Elders harness"
	@echo ""
	@echo "  make install [DEST=~/clan-world]  Materialize runtime from source (idempotent)"
	@echo "  make setup            Ensure dirs + ttyd unit files (alias for install)"
	@echo "  make elders-up        Start all 4 Elder tmux sessions"
	@echo "  make elders-down      Kill all 4 Elder tmux sessions"
	@echo "  make elders-status    Show which sessions are alive"
	@echo "  make elder-N          Start one Elder (N = 1..4)"
	@echo "  make elders-greet     Inject /clear + /rename + /color into all 4 REPLs"
	@echo "  make elder-greet-N    Inject startup commands into one Elder"
	@echo "  make ttyd-up          Start all 4 ttyd readonly web services"
	@echo "  make ttyd-down        Stop all 4 ttyd services"
	@echo "  make ttyd-status      Show ttyd service state"
	@echo "  make seed-liquidity   (stub) Seed Unicorn Town liquidity pool"
	@echo ""
	@echo "Source $(ELDER_DIR)/aliases.sh for shell shortcuts."

# === Install — materialize runtime tree from source ===
#
# Idempotent. Safe to re-run. Will NOT clobber:
#   .env, agent-directive.secret.md, state/, existing CLAUDE.md (personality)
# WILL overwrite (source-controlled, always safe to update):
#   AGENTS.md, settings.json, skills/, run.sh, bin/, Makefile, aliases.sh

install:
	@echo "=== installing elder harness to $(DEST) ==="
	@mkdir -p "$(DEST)"/.claude/skills
	@mkdir -p "$(DEST)"/bin
	@cp -p "$(REPO_DIR)"/parent/AGENTS.md "$(DEST)"/AGENTS.md
	@ln -sf AGENTS.md $(DEST)/CLAUDE.md
	@cp -p "$(REPO_DIR)"/parent/.claude/settings.json "$(DEST)"/.claude/settings.json
	@for skill in cleared-context-start elder-base-context final-tick-continuity \
	              uniswap-arb-camping uniswap-market-overview \
	              uniswap-sell-immediate uniswap-sell-scheduled; do \
	    mkdir -p $(DEST)/.claude/skills/$$skill; \
	    cp -p "$(REPO_DIR)"/parent/.claude/skills/$$skill/SKILL.md \
	          "$(DEST)"/.claude/skills/$$skill/SKILL.md; \
	done
	@cp -p "$(REPO_DIR)"/Makefile "$(DEST)"/Makefile
	@cp -p "$(REPO_DIR)"/aliases.sh "$(DEST)"/aliases.sh
	@cp -p "$(REPO_DIR)"/bin/* "$(DEST)"/bin/
	@for n in $(ELDER_NUMBERS); do \
	    mkdir -p $(DEST)/elder-$$n/.claude; \
	    mkdir -p $(DEST)/elder-$$n/state/plugin-cache; \
	    mkdir -p $(DEST)/elder-$$n/state/outbox; \
	    if [ ! -e $(DEST)/elder-$$n/.claude/.credentials.json ]; then \
	        ln -sf $(HOME)/.claude/.credentials.json \
	               $(DEST)/elder-$$n/.claude/.credentials.json; \
	        echo "  [elder-$$n] credentials symlink created"; \
	    fi; \
	    sed 's/{{ELDER_NUMBER}}/'"$$n"'/g' \
	        $(REPO_DIR)/template/run.sh.template \
	        > $(DEST)/elder-$$n/run.sh; \
	    chmod +x $(DEST)/elder-$$n/run.sh; \
	    if [ ! -f $(DEST)/elder-$$n/.claude/CLAUDE.md ]; then \
	        cp -p $(REPO_DIR)/personalities/elder-$$n.md \
	              $(DEST)/elder-$$n/.claude/CLAUDE.md; \
	        echo "  [elder-$$n] CLAUDE.md installed"; \
	    else \
	        echo "  [elder-$$n] CLAUDE.md exists — skipped"; \
	    fi; \
	    echo "  [elder-$$n] ready at $(DEST)/elder-$$n"; \
	done
	@$(MAKE) --no-print-directory ttyd-units
	@echo ""
	@echo "Install complete → $(DEST)"
	@echo "  source $(DEST)/aliases.sh        # shell shortcuts"
	@echo "  make -C $(DEST) elders-up        # spawn elder sessions"
	@echo "  make -C $(DEST) ttyd-up          # start ttyd services (after elders are running)"

setup: install

# === ttyd systemd unit generation ===
#
# Writes 4 unit files at ~/.config/systemd/user/ttyd-elder-{1..4}.service.
# Idempotent — diff-and-write only when content changes.
# Uses printf directly (no source-tree dependency) so it works from installed DEST too.

ttyd-units:
	@echo "=== ensuring ttyd-elder-N.service units ==="
	@mkdir -p $(SYSTEMD_USER_DIR)
	@for n in $(ELDER_NUMBERS); do \
	    port=$$((38790 + $$n - 1)); \
	    unit=$(SYSTEMD_USER_DIR)/ttyd-elder-$$n.service; \
	    tmp=$$(mktemp); \
	    printf '[Unit]\nDescription=ttyd readonly web view for elder-%d tmux session\nDocumentation=https://github.com/tsl0922/ttyd\nAfter=default.target\n\n[Service]\nType=simple\nEnvironment=TZ=America/New_York\nExecStart=%%h/bin/ttyd -R -p %d -t fontSize=11 -t cursorStyle=bar tmux attach-session -t elder-%d\nRestart=on-failure\nRestartSec=5\nStandardOutput=journal\nStandardError=journal\n\n[Install]\nWantedBy=default.target\n' \
	        "$$n" "$$port" "$$n" > $$tmp; \
	    if ! cmp -s $$tmp $$unit 2>/dev/null; then \
	        mv $$tmp $$unit; \
	        echo "  wrote: $$unit (port $$port)"; \
	    else \
	        rm -f $$tmp; \
	        echo "  unchanged: $$unit"; \
	    fi; \
	done
	@systemctl --user daemon-reload || echo "  warning: systemctl --user daemon-reload unavailable — skipped"
	@for n in $(ELDER_NUMBERS); do \
	    systemctl --user enable ttyd-elder-$$n.service 2>&1 | grep -v "already enabled" || true; \
	done

# === Elder tmux session lifecycle ===

elders-up: $(addprefix elder-,$(ELDER_NUMBERS))
	@$(MAKE) --no-print-directory elders-status

# Inject /clear + /rename + /color into a running elder REPL via tmux send-keys.
# Slash commands are processed by the CC input layer, not by env or model — they
# have to be physically typed into the running REPL. Helper at bin/elder-inject-startup.sh.
elders-greet:
	@"$(ELDER_DIR)"/bin/elder-inject-startup.sh all

elder-greet-1: ; @"$(ELDER_DIR)"/bin/elder-inject-startup.sh 1
elder-greet-2: ; @"$(ELDER_DIR)"/bin/elder-inject-startup.sh 2
elder-greet-3: ; @"$(ELDER_DIR)"/bin/elder-inject-startup.sh 3
elder-greet-4: ; @"$(ELDER_DIR)"/bin/elder-inject-startup.sh 4

elder-%:
	@if tmux has-session -t elder-$* 2>/dev/null; then \
	    echo "[elder-$*] already running — attach with: tmux attach -t elder-$*"; \
	else \
	    tmux new-session -d -s elder-$* -c $(ELDER_DIR)/elder-$* $(ELDER_DIR)/elder-$*/run.sh; \
	    echo "[elder-$*] started"; \
	fi

elders-down:
	@for n in $(ELDER_NUMBERS); do \
	    if tmux has-session -t elder-$$n 2>/dev/null; then \
	        tmux kill-session -t elder-$$n && echo "[elder-$$n] killed"; \
	    else \
	        echo "[elder-$$n] not running"; \
	    fi; \
	done

elders-status:
	@echo "=== Elder tmux sessions ==="
	@tmux ls 2>/dev/null | grep -E '^elder-[1-4]:' || echo "  (none running)"

# === ttyd service lifecycle ===

ttyd-up:
	@for n in $(ELDER_NUMBERS); do \
	    systemctl --user start ttyd-elder-$$n.service && echo "[ttyd-elder-$$n] started" || echo "[ttyd-elder-$$n] FAILED"; \
	done
	@$(MAKE) --no-print-directory ttyd-status

ttyd-down:
	@for n in $(ELDER_NUMBERS); do \
	    systemctl --user stop ttyd-elder-$$n.service && echo "[ttyd-elder-$$n] stopped" || echo "[ttyd-elder-$$n] not running"; \
	done

ttyd-status:
	@echo "=== ttyd-elder-N services ==="
	@for n in $(ELDER_NUMBERS); do \
	    state=$$(systemctl --user is-active ttyd-elder-$$n.service 2>/dev/null); \
	    port=$$((38790 + $$n - 1)); \
	    echo "  ttyd-elder-$$n: $$state (port $$port)"; \
	done
	@echo ""
	@echo "Public URLs (via Caddy + cloudflared):"
	@for n in $(ELDER_NUMBERS); do \
	    echo "  https://cockpit.clan-world.com/elder-$$n-tty/"; \
	done

# === Stub: liquidity pool seeding ===
#
# Placeholder for the contract setup work. Will deploy initial UnicornTown
# liquidity, mint test tokens to elder wallets, etc. Wires into:
#   ~/code/clan-world/packages/contracts/script/SeedLiquidity.s.sol  (TODO)
#
# Required env vars (loaded from ~/code/clan-world/.env.local):
#   RPC_URL_PRIMARY, DEPLOYER_PRIVATE_KEY, CLAN_WORLD_CONTRACT_ADDRESS

seed-liquidity:
	@echo "TODO: implement liquidity pool seeding"
	@echo "  - cast send <UnicornTown> seed(...)"
	@echo "  - mint test gold/wood/stone to each elder wallet"
	@echo "  - verify on chain"
	@echo ""
	@echo "Will live at ~/code/clan-world/packages/contracts/script/SeedLiquidity.s.sol"
	@echo "and be invoked here via: forge script --rpc-url \$$RPC_URL_PRIMARY --broadcast"
	@exit 1
