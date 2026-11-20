# ChocolateyPackager.exe — distribution en un fichier

## Objectif

ChocolateyPackager dispose d'un projet **C# / Windows Forms, .NET 10** sous `src/ChocolateyPackager/`.

Le produit destiné aux utilisateurs est un **unique fichier ChocolateyPackager.exe**. Le binaire publié en mode autonome ne requiert pas d'installation séparée de .NET, de Chocolatey ou de PowerShell pour **fabriquer un package**. Les fonctions de génération et de validation sont réécrites en C# et n'appellent ni PowerShell ni les anciens scripts.

**Attention :** Chocolatey utilise toujours `tools/chocolateyInstall.ps1` **à l'intérieur du fichier .nupkg créé**. Il s'agit du format de package Chocolatey, et non d'un script à distribuer à côté de l'EXE. Chocolatey doit être installé sur les postes cibles.

## Compiler depuis Windows

Prérequis pour le développeur uniquement : **SDK .NET 10** et Windows. Depuis la racine du dépôt :

```powershell
dotnet publish .\src\ChocolateyPackager\ChocolateyPackager.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:PublishTrimmed=false -o .\dist\win-x64
```

Le résultat attendu est **dist\win-x64\ChocolateyPackager.exe**, sans autre fichier à fournir à l'utilisateur. Le runtime inclus peut extraire ses dépendances natives dans le dossier temporaire de .NET au lancement : ceci ne change pas la distribution en un seul EXE.

### Test de l'EXE (non destructif)

Après compilation sur Windows :

```powershell
Start-Process -FilePath ".\dist\win-x64\ChocolateyPackager.exe" -ArgumentList '--self-test','--report',"$env:TEMP\chocolatey-packager-test.txt" -Wait -PassThru
```

Consultez ensuite le rapport dans le dossier temporaire. Le test crée un faux PE, génère un .nupkg, vérifie NuSpec + SHA-256 et refuse une archive corrompue. Aucun logiciel n'est installé.

Une validation supplémentaire doit être faite **manuellement sur une VM Windows** avec un vrai MSI/EXE et Chocolatey : installation, journaux, redémarrage, mise à jour et désinstallation.

## Compiler via GitHub (facultatif)

Le workflow `.github/workflows/windows-single-exe.yml` fonctionne **manuellement** (Actions → Build Windows single EXE → Run workflow) ou **sur les Pull Requests qui modifient l'application C#**. Il ne se lance pas à chaque commit sur `main`.

Il compile sur Windows, vérifie la présence d'un unique fichier EXE, exécute le test non destructif et publie un artefact téléchargeable nommé ChocolateyPackager-win-x64.

**L'EXE n'est pas considéré construit ou validé tant qu'une compilation Windows réelle n'a pas réussi.**

## État de la migration

- Nouveau parcours natif : sélection EXE/MSI, analyse, métadonnées éditables, création .nupkg et validation statique.
- Les anciens fichiers PowerShell et Start.cmd sont temporairement conservés comme **version de repli**, jusqu'à confirmation des tests Windows.
- Les archives ZIP, MSIX, les scripts de désinstallation sur mesure et l'édition complète des packages existants ne sont pas encore implémentés dans le nouveau moteur.
- Le projet est indépendant de Chocolatey Software et ne confère aucun droit de redistribution sur les installateurs tiers.

Référence Microsoft : [Publier une application .NET en un seul fichier](https://learn.microsoft.com/fr-fr/dotnet/core/deploying/single-file/overview).
