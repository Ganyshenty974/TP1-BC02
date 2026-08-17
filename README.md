# deploy.sh — Script de déploiement automatisé

## Objectif

Ce script automatise le déploiement d'une application web sur un serveur
de test (un conteneur Docker local) : clonage du dépôt Git, vérification
des dépendances, build de l'image Docker, déploiement du conteneur et
validation par health check. En cas d'échec du health check, la version
précédente de l'application est automatiquement restaurée (rollback).

Il répond aux objectifs DevOps de réduction du time-to-market et de
qualité constante à chaque déploiement, sans intervention manuelle.

## Prérequis

- `git`
- `docker`
- `curl`
- Un accès (SSH ou token) au dépôt Git de l'application à déployer

## Utilisation

Le script ne contient aucune valeur codée en dur : tout se configure via
des variables d'environnement, avec des valeurs par défaut raisonnables.

```bash
chmod +x deploy.sh
./deploy.sh
```

Exemple avec configuration personnalisée :

```bash
REPO_URL="git@github.com:Ganyshenty974/TP1-BC02.git" \
BRANCH="main" \
TEST_PORT=8080 \
./deploy.sh
```

### Variables disponibles

| Variable          | Rôle                                              | Valeur par défaut         |
|-------------------|----------------------------------------------------|----------------------------|
| `REPO_URL`        | URL du dépôt Git à déployer                        | dépôt de démo local        |
| `BRANCH`          | Branche à cloner                                    | `main`                     |
| `CLONE_DIR`       | Dossier local de clonage                            | `./workspace/demo-webapp`  |
| `IMAGE_NAME`      | Nom de l'image Docker construite                    | `demo-webapp`              |
| `IMAGE_TAG`       | Tag de l'image                                      | `latest`                   |
| `CONTAINER_NAME`  | Nom du conteneur déployé                            | `demo-webapp-test`         |
| `TEST_PORT`       | Port exposé sur l'hôte                              | `8080`                     |
| `CONTAINER_PORT`  | Port écouté par l'application dans le conteneur     | `3000`                     |
| `HEALTH_PATH`     | Route utilisée pour le health check                 | `/health`                  |
| `HEALTH_RETRIES`  | Nombre de tentatives du health check                | `5`                         |
| `HEALTH_DELAY`    | Délai (secondes) entre chaque tentative              | `2`                         |
| `LOG_FILE`        | Fichier de log de l'exécution                        | `deploy_<date>.log`        |

## Étapes du script

1. **Vérification des prérequis** — confirme que `git`, `docker` et
   `curl` sont installés avant de commencer, pour échouer tôt plutôt
   que tard.

2. **Clonage du dépôt** — supprime tout dossier de clonage existant
   (idempotence : chaque exécution repart d'un état propre), puis
   clone la branche demandée. Un échec (mauvaise URL, pas de droits...)
   arrête immédiatement le script avec un message explicite.

3. **Vérification des dépendances** — contrôle la présence de
   `package.json` et résout les dépendances (`npm install
   --package-lock-only`) pour détecter tout problème avant le build
   Docker, plus coûteux en temps.

4. **Sauvegarde de l'image précédente** — si une image du déploiement
   précédent existe, elle est retaguée `previous`. C'est cette image
   qui sera utilisée pour le rollback si besoin.

5. **Construction de l'image Docker** — `docker build` à partir du
   `Dockerfile` du projet. Un échec de build arrête le script.

6. **Déploiement du conteneur** — supprime systématiquement tout
   conteneur du même nom déjà existant avant de recréer (idempotence),
   puis lance le nouveau conteneur.

7. **Health check avec rollback automatique** — interroge la route
   `/health` de l'application (plusieurs tentatives espacées, car le
   démarrage peut prendre quelques secondes). Si toutes les tentatives
   échouent :
   - le conteneur défaillant est arrêté ;
   - si une image `previous` existe, elle est redéployée automatiquement ;
   - sinon, le script s'arrête en signalant qu'une intervention
     manuelle est nécessaire.

## Idempotence

Le script peut être relancé autant de fois que nécessaire : le dossier
de clonage et le conteneur existant sont systématiquement nettoyés
avant recréation, évitant tout état incohérent.

## Tests effectués

### Déploiement réussi
`./deploy.sh` avec REPO_URL pointant vers ce dépôt : clonage, build,
déploiement et health check passent tous, l'application est accessible
sur http://localhost:8080.

### Échec volontaire — mauvaise URL
```bash
REPO_URL="git@github.com:Ganyshenty974/depot-inexistant.git" ./deploy.sh
```
Le script échoue proprement dès l'étape de clonage, sans toucher au
conteneur en cours de fonctionnement.

### Rollback automatique
La route `/health` a été volontairement cassée (retour HTTP 500), puis
poussée sur le dépôt. Un nouveau `./deploy.sh` a détecté l'échec du
health check après 5 tentatives, puis restauré automatiquement la
version précédente (`demo-webapp:previous`), rétablissant le service
sans intervention manuelle.

## Logs

Chaque exécution produit un fichier `deploy_<date>_<heure>.log`
contenant l'horodatage de chaque étape, utile pour l'audit et le
diagnostic en cas de problème.
