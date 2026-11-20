<div align="center">

# 📦 Chocolatey Packager

**Transformez un installateur Windows MSI ou EXE en paquet Chocolatey autonome, depuis une interface graphique.**

[![Version](https://img.shields.io/badge/version-0.3.0-blue?style=flat-square)](https://github.com/neosoda/ChocolateyPackager)
![Windows](https://img.shields.io/badge/platform-Windows-0078D4?style=flat-square&logo=windows)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE?style=flat-square&logo=powershell)
![État](https://img.shields.io/badge/statut-bêta-orange?style=flat-square)

**Français** · [English](README.en.md)

</div>

---

## L'idée

Créer un paquet Chocolatey ne devrait pas nécessiter une journée de recherche ou une chaîne d'outils compliquée. **Chocolatey Packager** propose une petite application Windows portable : sélectionnez un `.msi` ou `.exe`, contrôlez les métadonnées et les paramètres d'installation silencieuse, puis créez un `.nupkg` contenant l'installateur.

Le projet est né d'un besoin de **déploiement de logiciels sur un parc informatique scolaire**, avec des dépôts internes et des réseaux filtrés. Il reste **générique** : vous pouvez l'utiliser sur votre propre poste, dans un laboratoire ou dans une entreprise, indépendamment de FOG.

## ✨ Ce qui fonctionne dans la v0.3.0

| Fonction | Détail |
| --- | --- |
| 🪟 Interface graphique | Application WinForms, sélection et glisser-déposer de MSI/EXE |
| 🔎 Analyse statique | Détection des métadonnées MSI et recherche de signatures dans les EXE **sans les exécuter** |
| 🧩 Arguments silencieux | MSI (`/qn`), Inno Setup, NSIS, WiX Burn et Everything ; identification partielle d'autres moteurs |
| 🏷️ Identifiants propres | Normalisation de l'identifiant du paquet ; ancien suffixe `-cmil` supprimé |
| 📦 Paquets autonomes | Installateur embarqué avec manifeste `.nuspec` et script Chocolatey |
| 🔐 Intégrité | Contrôle SHA-256 à la création, dans le paquet et après copie |
| 🗂️ Dépôt personnalisable | Dossier local ou partage réseau SMB, sans écraser un paquet existant |
| 🧪 Test structurel | Script de test sans installation d'application |

**Aucune installation de Chocolatey, NuGet, Docker ou Python n'est requise sur le PC qui _fabrique_ le paquet.** Le projet utilise Windows PowerShell 5.1 et les composants Windows/.NET intégrés.

> [!IMPORTANT]
> **Bêta v0.3.0.** La structure d'un paquet n'atteste pas qu'un logiciel s'installe ou se désinstalle correctement. Les paramètres EXE déduits de signatures doivent être confirmés avec la documentation de l'éditeur, puis testés sur une VM. Le générateur n'exécute jamais l'installateur pendant l'analyse.

## 🧰 Nouveautés de la branche de développement

Le parcours de création existant est conservé. L'interface permet maintenant de modifier **l'éditeur, la description et l'URL officielle HTTPS** du logiciel avant création. Ces informations sont inscrites dans le `.nuspec` avec échappement XML.

Un **validateur indépendant** (`Validateur-Paquet.ps1` (moteur) / `Verifier-Paquet.ps1` (CLI)) est exécuté **avant publication** : présence du manifeste et du script d'installation, syntaxe PowerShell, métadonnées obligatoires, cohérence du manifeste interne et SHA-256 de l'installateur embarqué. Les problèmes bloquants interrompent la création ; les autres sont des avertissements ou conseils. Un bouton **Valider un .nupkg** permet aussi d'inspecter un paquet existant.

Depuis Windows PowerShell 5.1 :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Verifier-Paquet.ps1" -PackagePath "C:\Packages\monlogiciel.1.0.0.nupkg"
```

Voir [Validation et tests réels](docs/VALIDATION.md) et [Références et licences](docs/REFERENCES.md). **Ces nouveautés n'ont pas encore été validées par un test Windows réel dans cette contribution.** Elles ne garantissent pas qu'un installateur accepte les options silencieuses proposées.

## 🚀 Démarrage rapide

1. Téléchargez le code depuis **[Code → Download ZIP](https://github.com/neosoda/ChocolateyPackager/archive/refs/heads/main.zip)** ou clonez le dépôt.
2. Décompressez tous les fichiers dans un même dossier sur **Windows 10/11 ou Windows Server**, avec **Windows PowerShell 5.1**.
3. Double-cliquez sur **`Lancer.cmd`**.
4. Sélectionnez ou glissez-déposez un MSI ou EXE.
5. Vérifiez l'identifiant, la version, les **arguments silencieux** et la destination.
6. Cliquez sur **Créer le paquet .nupkg**.

Le résultat est un fichier `identifiant.version.nupkg`, directement dans le dossier choisi.

### Exemple : Everything

Pour `Everything-1.4.1.1032.x64-Setup.exe`, le détecteur peut proposer :

| Champ | Exemple |
| --- | --- |
| Identifiant | `everything` |
| Version | `1.4.1.1032` |
| Arguments EXE | `/S` |
| Destination | `C:\Chocolatey-Packages` ou un partage réseau |
| Fichier généré | `everything.1.4.1.1032.nupkg` |

L'installation silencieuse d'Everything doit tout de même être validée sur un poste de test.

## 🏗️ Comment ça marche ?

```text
Lancer.cmd
   └── CMIL-Packager.ps1              interface graphique WinForms
        ├── Detecteur-Installateur.ps1 analyse locale, arguments proposés
        └── Moteur-Packager.ps1        nuspec + script Chocolatey + EXE/MSI
                                     contrôles SHA-256 + publication .nupkg
```

Le paquet contient notamment :

```text
myapp.1.2.3.nupkg
├── myapp.nuspec
└── tools/
    ├── chocolateyInstall.ps1
    ├── installer.exe (ou installer.msi)
    └── packager-info.json
```

Les fichiers générés sont vérifiés structurellement. **Aucune connexion Internet n'est nécessaire pendant la fabrication**. Cela ne garantit pas qu'un installeur de type « web bootstrapper » fonctionnera hors ligne : privilégiez un **installateur complet**.

## 🧪 Tester avant un déploiement réel

Dans PowerShell, depuis le dossier du projet :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Test-Automatique.ps1"
```

Ce test crée un **faux EXE** pour vérifier la reconnaissance, le manifeste, les fichiers intégrés et les empreintes. **Il ne teste pas Chocolatey, les commutateurs silencieux ni l'installation Windows.**

Après création, sur une **VM de test où Chocolatey est installé** :

```powershell
choco install everything --version 1.4.1.1032 --source="C:\Chocolatey-Packages" -y --no-progress
```

Adaptez le chemin à votre dépôt. Contrôlez ensuite le logiciel, les journaux Chocolatey, le code de retour et, si nécessaire, le redémarrage. Faites également un test de mise à jour/désinstallation avant une diffusion à grande échelle.

## 🏢 Dépôt réseau et intégration FOG

Le dépôt est simplement **le dossier contenant les `.nupkg`**. Exemple : `\\SERVEUR-DATA\Deploiement$\CHOCOLATEY`. Aucun chemin de serveur privé n'est imposé par le projet ; choisissez-le dans l'application.

Dans **FOG 1.6**, pour une configuration disposant du module Software/Chocolatey :

| Paramètre | Exemple |
| --- | --- |
| Backend | `Chocolatey` |
| Package | `everything` |
| Source | `\\SERVEUR-DATA\Deploiement$\CHOCOLATEY` |
| État souhaité | `Present` |

**Prérequis sur le poste cible :** Chocolatey fonctionnel, module Software FOG activé et accès au dépôt depuis le **compte sous lequel tourne l'agent** (souvent `SYSTEM`, utilisant le compte machine sur SMB). Le générateur de paquet ne configure ni Chocolatey ni FOG automatiquement.

Pour les grands parcs, un **dépôt NuGet/Chocolatey interne HTTP(S)** est généralement plus adapté qu'un simple partage SMB.

## ⚠️ Limites connues

- Les commutateurs **EXE ne sont pas universels**. InstallShield, Advanced Installer et d'autres moteurs peuvent nécessiter des arguments spécifiques ; le générateur laisse le champ vide en cas de doute.
- Les installateurs **qui téléchargent leur contenu** ne deviennent pas autonomes par le seul fait d'être embarqués.
- La v0.3.0 **ne génère pas automatiquement de désinstallation personnalisée pour tous les EXE** ; les scénarios de mise à niveau/désinstallation doivent être testés.
- Les métadonnées déduites du nom de fichier peuvent être inexactes : **vérifiez toujours l'identifiant, la version et la licence**.
- Les tests embarqués sont **structurels**. Une validation Windows + Chocolatey + FOG de bout en bout reste à effectuer dans l'environnement cible.
- Vérifiez la provenance, la signature numérique, les licences et les droits de redistribution des installateurs avant de partager les paquets.

## 🗺️ Suite du projet

- [ ] Valider les paquets générés avec des installations réelles Chocolatey sur plusieurs moteurs.
- [ ] Ajouter un assistant de désinstallation et des stratégies de mise à jour.
- [ ] Améliorer la détection des paramètres silencieux, avec références éditeur et scores de confiance.
- [ ] Ajouter des tests automatisés sur Windows et une interface de prévisualisation du `.nuspec`.
- [ ] Proposer une publication contrôlée vers des dépôts internes HTTP(S).

## 🤝 Contributions

Les retours de terrain, les exemples d'installateurs difficiles et les corrections sont bienvenus via les [Issues](https://github.com/neosoda/ChocolateyPackager/issues) et les pull requests. Ne joignez pas d'installateurs commerciaux, de secrets ni de données internes aux tickets publics.

---

<sub>Chocolatey Packager est un projet communautaire indépendant ; il n'est pas affilié à Chocolatey Software, FOG Project ni aux éditeurs des logiciels empaquetés. Version actuelle : **0.3.0**, en cours de validation.</sub>