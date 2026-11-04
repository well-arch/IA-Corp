#!/usr/bin/env bash
# Validation hors ligne : ne contacte aucun serveur de la plateforme. Docker sert
# uniquement à exécuter les vrais validateurs (nft, caddy, promtool), s'il est présent.
#   tests/validate.sh lint | all
set -euo pipefail

mode="${1:-all}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
render="$root/.render"
export ANSIBLE_CONFIG="$root/ansible/ansible.cfg"
cd "$root"

caddy_image=docker.io/library/caddy:2.11.7-alpine
prom_image=docker.io/prom/prometheus:v3.15.1
nft_image=docker.io/library/alpine:3.22

step() { printf '\n=== %s\n' "$*"; }

step "yamllint"
yamllint -s ansible tests .yamllint

step "Syntaxe des playbooks"
for playbook in site verify render; do
  (cd ansible && ansible-playbook -i ../tests/inventory --syntax-check "playbooks/$playbook.yml") >/dev/null
  echo "ok $playbook"
done

step "ansible-lint"
(cd ansible && ansible-lint --offline -q playbooks roles)

step "Scripts"
python3 -m py_compile scripts/gen-secrets.py scripts/models.py
bash -n scripts/mirror-images.sh tests/validate.sh ansible/roles/core_stack/files/postgres-init.sh
command -v shellcheck >/dev/null && shellcheck scripts/mirror-images.sh tests/validate.sh ansible/roles/core_stack/files/postgres-init.sh

[[ "$mode" == lint ]] && exit 0

rm -rf "$render"
for profile in production pilot; do
  for ldap in true false; do
    out="$render/$profile-ldap-$ldap"
    step "Rendu : profil $profile, LDAP $ldap"
    (cd ansible && ansible-playbook -i ../tests/inventory playbooks/render.yml \
      -e "ia_render_dir=$out ia_gpu_profile=$profile ia_ldap_enabled=$ldap" >/dev/null)

    python3 - "$out/test-core/core/keycloak/realm.json" <<'PY'
import json, sys
realm = json.load(open(sys.argv[1], encoding="utf-8"))
assert {c["clientId"] for c in realm["clients"]} == {"open-webui", "grafana", "langfuse"}
assert not any(c["directAccessGrantsEnabled"] for c in realm["clients"])
print("ok realm.json")
PY
    python3 -c "import json,sys; json.load(open(sys.argv[1]))" \
      "$root/ansible/roles/core_stack/files/dashboard-plateforme.json"

    if ! python3 - "$out" <<'PY'
import sys, yaml, pathlib
out = pathlib.Path(sys.argv[1])
for name in ["test-core/core/litellm/config.yaml", "test-core/core/prometheus/prometheus.yml",
             "test-core/core/grafana/provisioning/datasources/prometheus.yml"]:
    yaml.safe_load((out / name).read_text(encoding="utf-8"))
config = yaml.safe_load((out / "test-core/core/litellm/config.yaml").read_text(encoding="utf-8"))
assert config["litellm_settings"]["turn_off_message_logging"] is True
assert config["general_settings"]["store_prompts_in_spend_logs"] is False
# Deux serveurs GPU dans l'inventaire de test : chaque alias doit y figurer deux fois.
names = [m["model_name"] for m in config["model_list"]]
assert all(names.count(name) == 2 for name in names), names
print("ok litellm, prometheus, grafana")
PY
    then exit 1; fi

    if command -v docker >/dev/null; then
      for host in test-core/core test-gpu-1/gpu; do
        docker compose --project-directory "$out/$host" -f "$out/$host/compose.yml" config -q
        echo "ok compose $host"
      done
      for host in test-core test-gpu-1; do
        docker run --rm --cap-add NET_ADMIN -v "$out/$host/nftables.conf:/n.conf:ro" "$nft_image" \
          sh -c 'apk add -q nftables >/dev/null && nft -c -f /n.conf'
        echo "ok nftables $host"
      done
      for host in test-core/core test-gpu-1/gpu; do
        # Le TLS n'est pas chargé par « caddy adapt » : pas besoin de vrais certificats.
        docker run --rm -v "$out/$host/Caddyfile:/C:ro" "$caddy_image" \
          caddy adapt --config /C --adapter caddyfile >/dev/null
        echo "ok caddy $host"
      done
      docker run --rm --entrypoint promtool -v "$out/test-core/core/prometheus:/p:ro" "$prom_image" \
        check rules /p/rules.yml >/dev/null
      echo "ok règles prometheus"
    fi
  done
done

step "Validation terminée"
