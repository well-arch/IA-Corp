#!/usr/bin/env bash
# Recopie toutes les images figées vers un registre interne, depuis un poste relié à
# Internet et connecté à ce registre (skopeo login). Le chemin d'origine est conservé.
#
#   scripts/mirror-images.sh registry.exemple.local/miroir/
#   puis dans l'inventaire : ia_image_mirror: "registry.exemple.local/miroir/"
set -euo pipefail

prefix="${1:?usage : $0 <préfixe du registre, avec / final>}"
[[ "$prefix" == */ ]] || { echo "Le préfixe doit finir par /" >&2; exit 2; }
command -v skopeo >/dev/null || { echo "skopeo est requis" >&2; exit 1; }

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
images="$(python3 -c '
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
print("\n".join(data["ia_images"].values()))
' "$root/ansible/roles/ia_defaults/defaults/main.yml")"

while read -r image; do
  echo "== $image"
  skopeo copy --all --preserve-digests "docker://$image" "docker://$prefix$image"
done <<<"$images"
