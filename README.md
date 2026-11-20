<div align="center">

# Chocolatey Packager

**Créez des paquets Chocolatey à partir d'installateurs MSI et EXE.**

[![Version](https://img.shields.io/badge/version-0.3.0-334155)](https://github.com/neosoda/ChocolateyPackager)
![Windows](https://img.shields.io/badge/Windows-10%2F11%2FServer-0078D4)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-4674BE)
![Statut](https://img.shields.io/badge/statut-b%C3%AAta-D97706)

**Français** · [English](README.en.md)

</div>

Chocolatey Packager est un outil Windows portable pour fabriquer des fichiers `.nupkg` sans installer Chocolatey sur le poste de préparation. Choisissez un installateur, vérifiez son nom, sa version et ses paramètres silencieux, puis choisissez où enregistrer le paquet.

## Fonctionnalités

- Interface graphique WinForms, sélection de fichier ou glisser-déposer.
- Lecture des propriétés MSI et analyse statique de signatures EXE, **sans exécuter les installateurs**.
- Suggestions de paramètres silencieux pour MSI, Inno Setup, NSIS, WiX Burn et certains installateurs connus. Les cas incertains sont signalés.
- Création d'un paquet autonome avec installateur embarqué, manifeste `.nuspec` et `chocolateyInstall.ps1`.
- Contrôles SHA-256 à la copie et après création du paquet.
- Sortie dans un dossier local ou un partage réseau, sans écraser un paquet existant.

**Prérequis :** Windows 10, 11 ou Server, et Windows PowerShell 5.1. Pas besoin de Chocolatey, NuGet, Python ou Docker pour *créer* les paquets.

## Démarrage

1. Téléchargez [le ZIP du dépôt](https://github.com/neosoda/ChocolateyPackager/archive/refs/heads/main.zip) et extrayez-le dans un dossier.
2. Double-cliquez sur **`Start.cmd`**.
3. Sélectionnez un fichier `.msi` ou `.exe`.
4. Vérifiez l'identifiant, la version, les arguments silencieux et le répertoire de sortie.
5. Cliquez sur **Créer le paquet .nupkg**.

Le paquet généré suit le format `identifiant.version.nupkg`.

### Exemple

Avec l'installateur `Everything-1.4.1.1032.x64-Setup.exe`, l'application peut proposer l'identifiant `everything`, la version `1.4.1.1032` et l'argument `/S`. Le fichier obtenu est `everything.1.4.1.1032.nupkg`.

L'argument reste à confirmer avec la documentation de l'éditeur et par un test d'installation.

## Vérifier un paquet

Le projet contient un test de structure qui n'installe rien :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\SelfTest.ps1"
```

Pour valider **l'installation réelle**, utilisez une machine Windows de test avec Chocolatey :

```powershell
choco install everything --version 1.4.1.1032 --source="C:\Packages" -y --no-progress
```

Adaptez le dossier et le nom du paquet. Contrôlez le résultat, les journaux, puis les scénarios de mise à jour et de désinstallation avant toute diffusion.

## Fichiers du projet

```text
Start.cmd                 Lance l'interface
ChocolateyPackager.ps1    Interface graphique
InstallerDetector.ps1     Analyse MSI / EXE
PackageBuilder.ps1        Génération et vérification des .nupkg
SelfTest.ps1              Tests structurels non destructifs
QUICKSTART.txt            Aide de démarrage FR/EN
```

Le paquet contient notamment `identifiant.nuspec`, `tools/chocolateyInstall.ps1`, l'installateur embarqué et `tools/packager-info.json`.

## Limites de la version 0.3.0

- **Un EXE n'a pas de paramètre silencieux universel.** Une signature d'installateur permet une suggestion, pas une garantie. Si le moteur est inconnu, il faut vérifier la documentation de l'éditeur.
- Les installateurs qui téléchargent des fichiers pendant leur exécution nécessitent toujours une connexion réseau : les intégrer dans un `.nupkg` ne les rend pas autonomes.
- Le projet vérifie la **structure et l'intégrité** du paquet, pas la réussite d'une installation. Les tests Windows + Chocolatey restent nécessaires.
- Les scripts de désinstallation spécifiques à chaque logiciel ne sont pas encore générés automatiquement.
- Vérifiez les licences et les droits de redistribution avant de partager un paquet contenant un installateur tiers.

## Suite du projet

- Tests d'installation Windows automatisés pour plusieurs moteurs d'installation.
- Gestion de la désinstallation et des mises à jour.
- Détection plus précise des arguments avec références et indicateurs de confiance.
- Prévisualisation des scripts et publication vers un dépôt Chocolatey/NuGet.

Pour signaler un problème ou proposer une amélioration : [GitHub Issues](https://github.com/neosoda/ChocolateyPackager/issues).

<sub>Projet indépendant, sans affiliation avec Chocolatey Software. Version **0.3.0 bêta** : à valider sur machine de test avant tout déploiement.</sub>