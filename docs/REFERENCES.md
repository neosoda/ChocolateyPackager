# Références techniques et licences

Cette première évolution se base sur les documentations officielles sans importer de code tiers.

| Référence | Usage | Réutilisation de code |
| --- | --- | --- |
| [Chocolatey — Create Packages](https://docs.chocolatey.org/en-us/create/create-packages/) | Format `.nuspec`, scripts, création et essais | Aucune |
| [Chocolatey — Helpers](https://docs.chocolatey.org/en-us/create/functions/) | Utilisation documentée de `Install-ChocolateyInstallPackage` | Aucune |
| [Chocolatey — Commands](https://docs.chocolatey.org/en-us/create/commands/) | Commandes `pack`, `install`, `push` | Aucune |
| [Chocolatey — Validator Rules](https://docs.chocolatey.org/en-us/community-repository/moderation/package-validator/rules/) | Règles de qualité et recommandations pour les métadonnées et scripts | Aucune |
| [chocolatey/choco](https://github.com/chocolatey/choco) | Référence de l'implémentation du moteur Chocolatey | Aucune |
| [chocolatey-community/chocolatey-community-validation](https://github.com/chocolatey-community/chocolatey-community-validation) | Exemples de règles de validation ; projet indiqué Apache-2.0 sur GitHub lors de la consultation | Aucune |

**Licences :** aucune source tierce n'a été copiée dans cette contribution. Les licences et permissions doivent être revérifiées avant toute future intégration de bibliothèque. Une proposition de licence **Apache-2.0 + Commons Clause 1.0** est documentée dans le fichier racine [`LICENSE`](../LICENSE) pour le code original du projet. Cette combinaison est **source-available, non open source**. Les licences des outils et installateurs tiers ne sont pas modifiées par cette proposition. Le mainteneur doit choisir et publier explicitement une licence avant d'annoncer le projet comme légalement open source.

Les installateurs de logiciels tiers ne sont pas inclus dans le dépôt : respecter leurs licences et droits de redistribution avant tout empaquetage.
