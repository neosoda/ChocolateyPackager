# Chocolatey Packager v0.4.0-beta.1

Première **préversion Windows native** sous la forme d'un seul fichier `ChocolateyPackager.exe`, sans installateur, ni dossier de scripts, ni installation préalable de .NET sur le poste qui fabrique les packages.

### Nouveautés
- Interface graphique Windows (WinForms / .NET 10), sélection et glisser-déposer de fichiers MSI ou EXE.
- Analyse statique des installateurs, identification de moteurs connus et propositions d'options silencieuses **à vérifier**.
- Création directe de packages Chocolatey `.nupkg` avec manifest NuSpec et installateur embarqué.
- Validation statique de la structure OPC/NuGet, des métadonnées et des empreintes SHA-256.
- Fichier `.sha256` fourni pour vérifier l'intégrité du téléchargement.
- Compilation `win-x64` autonome : pas d'installation séparée de PowerShell, du runtime .NET ou de Chocolatey **sur le poste de création**.

### Installation
Téléchargez **ChocolateyPackager.exe** dans les fichiers joints à cette release et exécutez-le sous Windows x64. Aucun autre fichier n'est nécessaire. Windows peut afficher un avertissement SmartScreen car le binaire n'est pas signé numériquement.

Chocolatey est toujours nécessaire **sur les postes cibles** pour installer les `.nupkg` générés. Les scripts Chocolatey restent intégrés *dans les packages produits*, pas à côté de l'EXE.

### Vérification
Le workflow de build doit compiler l'EXE sur Windows et réussir un test automatisé non destructif (faux PE, génération `.nupkg`, SHA-256, rejet d'archive corrompue) avant la publication.

**Limite bêta :** le logiciel n'a pas été validé par des installations, mises à jour et désinstallations réelles sur des VM Windows. Les paramètres silencieux EXE ne sont pas garantis et les droits de redistribution des installateurs restent à respecter. Testez vos packages sur une VM avant de les déployer.

Documentation : [README](https://github.com/neosoda/ChocolateyPackager#readme) · [Générer l'EXE autonome](https://github.com/neosoda/ChocolateyPackager/blob/main/docs/EXECUTABLE.md).
