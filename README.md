# MuniAnalyse

MuniAnalyse est l'outil specialise d'analyse documentaire de la suite Orchiviste/Muni.

## Mission

Fournir une analyse texte deterministe exploitable via contrat CLI JSON V1, sans OCR dans cette phase.

## Positionnement

- Outil autonome executable localement.
- Integrable dans Orchiviste (cockpit/hub) via contrat commun OrchivisteKit.

## Contrat CLI JSON V1

Commande canonique:

```bash
muni-analyse-cli run --request /path/request.json --result /path/result.json
```

Entrees V1 supportees:

- `parameters.text` (texte inline)
- `parameters.source_path` (chemin ou `file://` vers un fichier texte)
- `input_artifacts[]` de type `input` (URI fichier)
- `parameters.report_path` optionnel pour produire un rapport JSON d'analyse

Sorties:

- `ToolResult` canonique dans `--result`
- statut nominal: `succeeded` ou `needs_review`
- statut d'erreur: `failed`

## Build et tests

```bash
swift package resolve
swift build
swift test
```

## Licence

GNU GPL v3.0, voir [LICENSE](LICENSE).
