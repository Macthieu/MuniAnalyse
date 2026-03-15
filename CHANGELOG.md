# Changelog

Toutes les modifications notables de ce projet seront documentees dans ce fichier.

Le format s'inspire de Keep a Changelog et le projet suit Semantic Versioning.

## [Unreleased]

### Changed
- Remplacement des contrats locaux dupliques par `OrchivisteKitContracts`.
- Intégration de `OrchivisteKitInterop` pour la lecture/ecriture canonique `ToolRequest/ToolResult`.

### Added
- Activation V1 du mode canonique `muni-analyse-cli run --request <file> --result <file>`.
- Pipeline d'analyse texte deterministe (comptages, phrases, paragraphes, top termes, apercu).
- Option `report_path` pour produire un artefact JSON d'analyse exploitable.
- Tests unitaires interop/canonique (succes, needs_review, erreurs, artefact rapport).
- Versionnage de `Package.resolved` avec pin OrchivisteKit `0.2.0`.

### Removed
- Placeholder nominal `not_implemented` sur le chemin d'execution canonique.

## [0.1.0] - 2026-03-14

### Added
- Version initiale de normalisation du dépôt.
- README, CONTRIBUTING et licence harmonisés pour publication GitHub.
