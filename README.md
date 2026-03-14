# MuniAnalyse

MuniAnalyse est l'outil specialise correspondant dans la suite documentaire municipale Orchiviste/Muni.

## Mission

Ce depot fournit le socle executable minimal (Core + CLI) pour l'integration V1 via CLI JSON local.

## Positionnement

- Outil autonome executables seul.
- Integrable dans Orchiviste (cockpit/hub) via contrat commun CLI JSON.

## Contrat CLI JSON V1

Commande:

```bash
muni-analyse-cli run --request /path/request.json --result /path/result.json
```

Valeurs autorisees de `status`:

- `queued`
- `running`
- `succeeded`
- `failed`
- `needs_review`
- `cancelled`
- `not_implemented`

Le squelette actuel retourne `not_implemented` tant que la logique metier n'est pas implementee.

## Build et tests

```bash
swift build
swift test
```

## Licence

GNU GPL v3.0, voir [LICENSE](LICENSE).
