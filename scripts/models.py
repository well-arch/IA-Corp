#!/usr/bin/env python3
"""Gère les poids des modèles, à exécuter sur un poste relié à Internet.

  manifest          écrit les empreintes publiées par Hugging Face pour la révision
                    figée du catalogue, dans ansible/models/manifests/ (à versionner)
  download <dossier> [modèle…]
                    télécharge cette révision, puis contrôle chaque fichier

Le serveur GPU ne contacte jamais Hugging Face : il reçoit les fichiers par
`make models-push` et les vérifie de nouveau au déploiement (rôle models).
"""
import hashlib
import json
import subprocess
import sys
import urllib.request
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "ansible/roles/ia_defaults/defaults/main.yml"
MANIFESTS = ROOT / "ansible/models/manifests"
WEIGHT_SUFFIXES = (".safetensors", ".bin")
# Fichiers à ne jamais récupérer : autres formats des mêmes poids.
EXCLUDES = ["*.onnx", "*.onnx_data", "onnx/*", "*.gguf", "*.h5", "*.msgpack", "imgs/*"]


def catalog() -> dict:
    return yaml.safe_load(CATALOG.read_text(encoding="utf-8"))["ia_model_catalog"]


def upstream_files(model: dict) -> list[dict]:
    url = f"https://huggingface.co/api/models/{model['repo']}/revision/{model['revision']}?blobs=true"
    request = urllib.request.Request(url, headers={"User-Agent": "ia-corp-models"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)["siblings"]


def excluded(path: str) -> bool:
    return path.startswith(("onnx/", "imgs/")) or path.endswith(
        (".onnx", ".onnx_data", ".gguf", ".h5", ".msgpack")
    )


def weights_with_hash(name: str, model: dict) -> dict[str, str]:
    """Empreintes publiées (stockage LFS) pour les poids de cette révision."""
    result = {}
    for item in upstream_files(model):
        path = item["rfilename"]
        if excluded(path) or not path.endswith(WEIGHT_SUFFIXES):
            continue
        # Un dépôt peut publier deux jeux de poids : ne garder que le plus sûr.
        lfs = item.get("lfs")
        if lfs:
            result[path] = lfs["sha256"]
    if any(path.endswith(".safetensors") for path in result):
        result = {p: h for p, h in result.items() if p.endswith(".safetensors")}
    if not result:
        raise SystemExit(f"{name} : aucun fichier de poids trouvé")
    if any(p.endswith(".bin") for p in result) and not model.get("allow_pickle"):
        raise SystemExit(f"{name} : seul le format pickle est publié, sans allow_pickle")
    return result


def cmd_manifest() -> int:
    MANIFESTS.mkdir(parents=True, exist_ok=True)
    for name, model in catalog().items():
        hashes = weights_with_hash(name, model)
        lines = [f"{digest}  {path}\n" for path, digest in sorted(hashes.items())]
        (MANIFESTS / f"{name}.sha256").write_text("".join(lines), encoding="utf-8")
        print(f"{name} : {len(lines)} fichier(s)")
    return 0


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def cmd_download(target: str, names: list[str]) -> int:
    models = catalog()
    for name in names or list(models):
        if name not in models:
            raise SystemExit(f"Modèle inconnu : {name}")
        model = models[name]
        destination = Path(target) / name
        command = [
            "hf", "download", model["repo"],
            "--revision", model["revision"],
            "--local-dir", str(destination),
        ]
        for pattern in EXCLUDES:
            command += ["--exclude", pattern]
        print(f"== {name} : téléchargement de {model['repo']}")
        subprocess.run(command, check=True)

        manifest = MANIFESTS / f"{name}.sha256"
        for line in manifest.read_text(encoding="utf-8").splitlines():
            expected, relative = line.split("  ", 1)
            actual = sha256(destination / relative)
            if actual != expected:
                raise SystemExit(f"{name}/{relative} : empreinte différente ({actual})")
            print(f"   OK {relative}")
        # Métadonnées du téléchargement, inutiles et sources d'écritures sur le serveur.
        subprocess.run(["rm", "-rf", str(destination / ".cache")], check=True)
    return 0


def main() -> int:
    if len(sys.argv) >= 2 and sys.argv[1] == "manifest":
        return cmd_manifest()
    if len(sys.argv) >= 3 and sys.argv[1] == "download":
        return cmd_download(sys.argv[2], sys.argv[3:])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
