# Validation des packages — ChocolateyPackager

## Périmètre

Le validateur est **statique et hors ligne**. Il n'extrait ni n'exécute un installateur. Il inspecte la structure OPC/NuGet du `.nupkg`, le `.nuspec`, la syntaxe du script PowerShell et, pour les packages créés par ChocolateyPackager, l'empreinte SHA-256 de l'installateur intégré.

Sur Windows PowerShell 5.1, dans le dossier du projet :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Validateur-Paquet.ps1" -PackagePath "C:\Packages\monlogiciel.1.0.0.nupkg"
```

Le processus renvoie le **code 1** lorsqu'une erreur bloquante est détectée.

## Contrôles intégrés

- Manifeste `.nuspec` unique à la racine ; XML lu en désactivant les DTD.
- Identifiant, version, auteurs et description obligatoires.
- Présence de `tools/chocolateyInstall.ps1` et absence d'erreurs de syntaxe PowerShell.
- Avertissement sur `Invoke-Expression` ; recommandations sur les métadonnées.
- Cohérence de `packager-info.json` avec le `.nuspec`.
- Comparaison SHA-256 de l'installateur embarqué avec l'empreinte stockée dans le manifeste.
- Avertissement en l'absence de `installer.exe.ignore`.

**Important :** un package provenant d'un autre outil peut ne pas contenir `packager-info.json` ; cette absence est une recommandation, pas une erreur. Le validateur n'est pas une garantie de sécurité pour un package tiers et n'est pas un remplacement des contrôles réalisés par Chocolatey.

Pendant la création, ChocolateyPackager exécute le même validateur avant de publier le paquet. Les erreurs bloquent la publication. La fenêtre permet également de sélectionner et de vérifier un `.nupkg` déjà présent.

## Limites et tests réels

La validation ne certifie **pas** les paramètres silencieux, l'installation ou la désinstallation réelles, l'absence de malware, les droits de redistribution, ni la réussite d'une mise à niveau.

Tests recommandés sur **VM Windows jetable et isolée** :

1. Confirmer la provenance et les droits de redistribution du logiciel.
2. Vérifier le package via le validateur local.
3. Si Chocolatey CLI est disponible, confronter le résultat à `choco pack` sur un dossier de source équivalent.
4. Installer depuis un dépôt local en ciblant **l'identifiant** et non le fichier :
   ```powershell
   choco install monlogiciel --version 1.0.0 --source="C:\Packages" -y --no-progress
   ```
5. Vérifier processus, services, fichiers, registres, logs et codes de retour.
6. Tester désinstallation, installation d'une version supérieure et redémarrage.

Ne jamais utiliser `--force` comme comportement de production. Ne jamais tester un installateur inconnu directement sur le poste de travail.

## Tests du dépôt

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Test-Automatique.ps1"
```

Ce script emploie un **faux PE** purement statique et un `.nupkg` volontairement corrompu. Il ne démarre aucun installateur. Les résultats des tests Windows doivent être collectés avant de considérer une nouvelle version comme validée.
