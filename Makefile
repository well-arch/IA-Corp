.PHONY: help bootstrap init secrets vault-encrypt vault-edit check deploy verify models-manifest models-download models-push mirror-images lint validate
.DEFAULT_GOAL := help

ENV ?= prod
VENV := $(CURDIR)/.venv
BIN := $(VENV)/bin
INVENTORY := inventories/$(ENV)
export ANSIBLE_CONFIG := $(CURDIR)/ansible/ansible.cfg
# Déposer le mot de passe du vault dans ce fichier (exclu de Git), ou retirer l'option
# pour le saisir à chaque exécution.
VAULT_PASS := $(CURDIR)/.vault-pass-$(ENV)
ANSIBLE_ARGS := -i $(INVENTORY) $(if $(wildcard $(VAULT_PASS)),--vault-password-file $(VAULT_PASS),--ask-vault-pass)

help: ## affiche cette aide
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

bootstrap: ## installe l'outillage du poste d'administration dans .venv
	python3 -m venv $(VENV)
	$(BIN)/pip install -q -r requirements-dev.txt
	cd ansible && $(BIN)/ansible-galaxy collection install -r requirements.yml -p collections

init: ## crée l'environnement ENV à partir de l'exemple
	@test ! -e ansible/inventories/$(ENV) || { echo "ansible/inventories/$(ENV) existe déjà"; exit 1; }
	cp -r ansible/inventories/example ansible/inventories/$(ENV)
	python3 scripts/gen-secrets.py ansible/inventories/$(ENV)

vault-encrypt: ## chiffre les secrets de ENV
	cd ansible && $(BIN)/ansible-vault encrypt $(if $(wildcard $(VAULT_PASS)),--vault-password-file $(VAULT_PASS),) $(INVENTORY)/group_vars/all/vault.yml

vault-edit: ## modifie les secrets de ENV
	cd ansible && $(BIN)/ansible-vault edit $(if $(wildcard $(VAULT_PASS)),--vault-password-file $(VAULT_PASS),) $(INVENTORY)/group_vars/all/vault.yml

check: ## contrôle les prérequis des serveurs sans rien modifier
	cd ansible && $(BIN)/ansible-playbook $(ANSIBLE_ARGS) playbooks/site.yml --tags preflight

deploy: ## déploie ou met à jour ENV (rejouable)
	cd ansible && $(BIN)/ansible-playbook $(ANSIBLE_ARGS) playbooks/site.yml

verify: ## teste la plateforme déployée de bout en bout
	cd ansible && $(BIN)/ansible-playbook $(ANSIBLE_ARGS) playbooks/verify.yml

models-manifest: ## actualise les empreintes depuis Hugging Face
	$(BIN)/python scripts/models.py manifest

models-download: ## télécharge et contrôle les poids : make models-download DIR=/chemin [MODELS="a b"]
	@test -n "$(DIR)" || { echo "Préciser DIR=/chemin"; exit 1; }
	$(BIN)/python scripts/models.py download "$(DIR)" $(MODELS)

models-push: ## envoie les poids sur un serveur : make models-push DIR=/chemin HOST=user@ip
	@test -n "$(DIR)" -a -n "$(HOST)" || { echo "Préciser DIR=/chemin et HOST=user@ip"; exit 1; }
	rsync -a --partial --mkpath --info=progress2 --rsync-path="sudo rsync" "$(DIR)"/ "$(HOST):/srv/ia/models/"

mirror-images: ## recopie les images vers un registre : make mirror-images REGISTRY=reg.local/miroir/
	@test -n "$(REGISTRY)" || { echo "Préciser REGISTRY=reg.local/miroir/"; exit 1; }
	PATH="$(BIN):$$PATH" scripts/mirror-images.sh "$(REGISTRY)"

lint: ## yamllint, ansible-lint et contrôle de syntaxe
	PATH="$(BIN):$$PATH" tests/validate.sh lint

validate: ## lint, puis rendu et validation de toutes les configurations
	PATH="$(BIN):$$PATH" tests/validate.sh all
