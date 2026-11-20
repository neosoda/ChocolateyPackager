# Référencement naturel — ChocolateyPackager

## Ce qui est livré dans le dépôt

- README français et anglais structurés sur les intentions de recherche pertinentes (création d'un package Chocolatey, interface graphique Windows, MSI/EXE, .nupkg).
- Pages HTML statiques : `docs/index.html` (anglais) et `docs/fr.html` (français), CSS local sans dépendance externe.
- Balises HTML `title`, `description`, `canonical`, `hreflang`, Open Graph, données structurées `SoftwareApplication`, et `docs/sitemap.xml`.
- Aucun mot-clé répété artificiellement ni promesse de fonctionnalités absentes.

## Deux réglages manuels requis (GitHub)

Le connecteur de gestion du code ne permet pas de modifier directement les métadonnées « About » et de publier GitHub Pages. Le propriétaire doit effectuer ces opérations depuis GitHub.

### 1. Paramètres « About »

Dans la page d'accueil du dépôt, cliquez sur l'icône de configuration à droite de **About**.

**Description conseillée :**

> Chocolatey package builder GUI for Windows: create .nupkg packages from MSI/EXE installers with silent switch detection and SHA-256 validation.

**Topics recommandés (pertinents et non trompeurs) :**

`chocolatey`, `chocolatey-package`, `package-builder`, `windows`, `powershell`, `msi`, `exe`, `nupkg`, `silent-install`, `software-deployment`, `gui`, `sysadmin`.

Ne pas utiliser le topic « open-source » tant qu'un fichier LICENSE explicite n'est pas publié.

### 2. Publier le site avec GitHub Pages

Dans le dépôt : **Settings → Pages → Build and deployment → Deploy from a branch** puis choisir **main** et **/docs**, enregistrer.

Le site utilisera ces URLs (elles peuvent renvoyer 404 avant activation) :

- EN : https://neosoda.github.io/ChocolateyPackager/
- FR : https://neosoda.github.io/ChocolateyPackager/fr.html
- Sitemap : https://neosoda.github.io/ChocolateyPackager/sitemap.xml

Après activation, ajouter l'URL du site dans **About → Website**.

La page GitHub Pages doit être activée *avant* toute revendication d'indexation Google. Le sitemap est préparé mais pas encore soumis. Une publication sur GitHub Pages n'assure pas une indexation automatique.

## Après publication

- Tester les deux URLs et le sitemap en HTTP 200, vérifier canonicals et hreflang réciproques.
- Vérifier la présence du site et les éventuels problèmes d'indexation dans [Google Search Console](https://search.google.com/search-console/about). Soumettre l'URL du sitemap uniquement si le contrôle du site et la propriété du domaine sont confirmés.
- Mettre un lien vers la page GitHub Pages dans le README **uniquement lorsqu'elle fonctionne**.
- Faire connaître le projet naturellement par des démonstrations techniques authentiques et des retours d'expérience, sans achat de backlinks ou textes automatisés en masse.
- Ajouter plus tard une capture d'écran réelle (avec texte alternatif descriptif), après validation de l'interface sous Windows.
- Garder les titres, textes et références à jour après les prochaines releases ; aucun classement Google n'est garanti.

Références officielles :
- [Google Search Essentials](https://developers.google.com/search/docs/essentials)
- [GitHub — Classifying a repository with topics](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/classifying-your-repository-with-topics)
- [GitHub Pages](https://docs.github.com/en/pages/quickstart)
