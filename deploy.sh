#!/usr/bin/env bash
###############################################################################
# deploy.sh
#
# OBJECTIF
#   Script d'automatisation du déploiement d'une application web sur un
#   serveur de test (conteneur Docker local). Il couvre l'ensemble du
#   cycle : clonage du code, installation des dépendances, build de
#   l'image, déploiement du conteneur, validation (health check), et
#   rollback automatique en cas d'échec.
#
# USAGE
#   ./deploy.sh
#
#   Toute la configuration passe par des variables d'environnement
#   (voir section CONFIGURATION ci-dessous et le README.md). Exemple :
#
#   REPO_URL="git@github.com:mon-org/mon-app.git" \
#   TEST_PORT=8081 \
#   ./deploy.sh
#
# PRÉREQUIS : git, docker, curl installés sur la machine d'exécution.
###############################################################################

set -euo pipefail
# set -e   : arrête le script à la première commande qui échoue
# set -u   : erreur si une variable non définie est utilisée
# set -o pipefail : un pipe (cmd1 | cmd2) échoue si une seule des
#                   commandes échoue, pas seulement la dernière

# --- 1. CONFIGURATION (variables d'environnement) ---------------------------
# Exigence 7 du TP : rien n'est codé en dur. Chaque variable a une valeur
# par défaut (via ${VAR:-defaut}) mais peut être surchargée à l'appel du
# script, ce qui le rend réutilisable pour n'importe quel projet.

REPO_URL="${REPO_URL:-/home/claude/remote-repo.git}"
BRANCH="${BRANCH:-main}"
CLONE_DIR="${CLONE_DIR:-./workspace/demo-webapp}"
IMAGE_NAME="${IMAGE_NAME:-demo-webapp}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
CONTAINER_NAME="${CONTAINER_NAME:-demo-webapp-test}"
TEST_PORT="${TEST_PORT:-8080}"
CONTAINER_PORT="${CONTAINER_PORT:-3000}"
HEALTH_PATH="${HEALTH_PATH:-/health}"
HEALTH_RETRIES="${HEALTH_RETRIES:-5}"
HEALTH_DELAY="${HEALTH_DELAY:-2}"
LOG_FILE="${LOG_FILE:-deploy_$(date +%Y%m%d_%H%M%S).log}"

# Nom utilisé pour taguer l'image précédente avant d'en construire une
# nouvelle. Sert au mécanisme de rollback (exigence 6).
PREVIOUS_IMAGE_TAG="previous"

# --- 2. FONCTIONS UTILITAIRES ------------------------------------------------

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

fail() {
    log "ERREUR : $1"
    exit 1
}

check_dependency() {
    local cmd="$1"
    command -v "$cmd" &>/dev/null || fail "'$cmd' n'est pas installé."
    log "OK : $cmd est disponible."
}

# Rollback : relance le conteneur avec l'image précédente (tag "previous")
# si elle existe. Utilisé quand le health check final échoue.
rollback() {
    log "--- ROLLBACK déclenché ---"

    if ! docker image inspect "${IMAGE_NAME}:${PREVIOUS_IMAGE_TAG}" &>/dev/null; then
        log "Aucune version précédente disponible (${IMAGE_NAME}:${PREVIOUS_IMAGE_TAG} introuvable)."
        log "Impossible d'effectuer un rollback automatique. Arrêt du conteneur défaillant."
        docker rm -f "$CONTAINER_NAME" &>/dev/null || true
        fail "Déploiement échoué et aucun rollback possible. Intervention manuelle requise."
    fi

    log "Arrêt du conteneur défaillant..."
    docker rm -f "$CONTAINER_NAME" &>/dev/null || true

    log "Redémarrage du conteneur avec la version précédente (${IMAGE_NAME}:${PREVIOUS_IMAGE_TAG})..."
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "${TEST_PORT}:${CONTAINER_PORT}" \
        -e "PORT=${CONTAINER_PORT}" \
        --restart unless-stopped \
        "${IMAGE_NAME}:${PREVIOUS_IMAGE_TAG}" >/dev/null

    log "Rollback effectué. L'ancienne version est de nouveau en service sur le port ${TEST_PORT}."
    fail "Le nouveau déploiement a échoué au health check ; l'ancienne version a été restaurée."
}

# --- 3. VÉRIFICATION DES PRÉREQUIS ------------------------------------------

log "=== Démarrage du pipeline de déploiement ==="
log "Configuration : REPO_URL=$REPO_URL | BRANCH=$BRANCH | TEST_PORT=$TEST_PORT"

check_dependency "git"
check_dependency "docker"
check_dependency "curl"

# --- 4. ÉTAPE 1 : CLONAGE / MISE À JOUR DU DÉPÔT ----------------------------
# Idempotence (exigence 5) : si le dossier existe déjà, on nettoie
# systématiquement avant de recloner, plutôt que de laisser un état
# incertain (mélange d'anciens et de nouveaux fichiers).

log "Étape 1/5 : Clonage du dépôt Git"

if [ -d "$CLONE_DIR" ]; then
    log "Le dossier $CLONE_DIR existe déjà : suppression pour repartir d'un état propre."
    rm -rf "$CLONE_DIR"
fi

mkdir -p "$(dirname "$CLONE_DIR")"

if git clone --branch "$BRANCH" "$REPO_URL" "$CLONE_DIR" >>"$LOG_FILE" 2>&1; then
    log "OK : dépôt cloné avec succès dans $CLONE_DIR."
else
    fail "échec du clonage du dépôt Git ($REPO_URL, branche $BRANCH). Vérifiez l'URL et vos droits d'accès."
fi

cd "$CLONE_DIR"

# --- 5. ÉTAPE 2 : INSTALLATION DES DÉPENDANCES ------------------------------
# On installe les dépendances hors conteneur uniquement pour valider
# que package.json est cohérent avant de lancer un build Docker plus
# coûteux ; le build Docker réinstallera proprement dans l'image.

log "Étape 2/5 : Vérification des dépendances applicatives"

[ -f "package.json" ] || fail "aucun fichier package.json trouvé dans $CLONE_DIR."

if command -v npm &>/dev/null; then
    if npm install --package-lock-only --silent >>"../../$LOG_FILE" 2>&1; then
        log "OK : dépendances vérifiées (package-lock.json généré/à jour)."
    else
        fail "échec de la résolution des dépendances npm."
    fi
else
    log "npm non disponible sur l'hôte : la résolution des dépendances sera faite dans l'image Docker."
fi

# --- 6. ÉTAPE 3 : SAUVEGARDE DE L'IMAGE PRÉCÉDENTE (pour le rollback) -------
# Avant de construire la nouvelle image, on retague l'image existante
# (si elle existe) en "previous". C'est elle qui sera utilisée en cas
# d'échec du health check.

log "Étape 3/5 : Sauvegarde de l'image précédente si elle existe"

if docker image inspect "${IMAGE_NAME}:${IMAGE_TAG}" &>/dev/null; then
    docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${IMAGE_NAME}:${PREVIOUS_IMAGE_TAG}"
    log "OK : image actuelle sauvegardée sous ${IMAGE_NAME}:${PREVIOUS_IMAGE_TAG}."
else
    log "Aucune image précédente trouvée (premier déploiement)."
fi

# --- 7. ÉTAPE 4 : CONSTRUCTION DE L'IMAGE DOCKER ----------------------------

log "Étape 4/5 : Construction de l'image Docker (${IMAGE_NAME}:${IMAGE_TAG})"

[ -f "Dockerfile" ] || fail "aucun Dockerfile trouvé dans $CLONE_DIR."

if docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" . >>"../../$LOG_FILE" 2>&1; then
    log "OK : image Docker construite avec succès."
else
    fail "échec du build Docker. Consultez $LOG_FILE pour le détail."
fi

# --- 8. ÉTAPE 5 : DÉPLOIEMENT DU CONTENEUR ----------------------------------
# Idempotence : on supprime systématiquement tout conteneur existant du
# même nom avant de recréer, qu'il ait échoué ou non lors d'un run
# précédent (nettoyage systématique demandé par l'exigence 5).

log "Étape 5/5 : Déploiement du conteneur sur l'environnement de test"

if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    log "Un conteneur $CONTAINER_NAME existe déjà : arrêt et suppression."
    docker rm -f "$CONTAINER_NAME" >/dev/null
fi

if docker run -d \
    --name "$CONTAINER_NAME" \
    -p "${TEST_PORT}:${CONTAINER_PORT}" \
    -e "PORT=${CONTAINER_PORT}" \
    --restart unless-stopped \
    "${IMAGE_NAME}:${IMAGE_TAG}" >>"../../$LOG_FILE" 2>&1; then
    log "OK : conteneur démarré (port hôte $TEST_PORT -> port conteneur $CONTAINER_PORT)."
else
    fail "échec du démarrage du conteneur."
fi

# --- 9. VALIDATION : HEALTH CHECK avec ROLLBACK automatique -----------------
# On réessaie plusieurs fois (HEALTH_RETRIES) avec un délai, car
# l'application peut mettre quelques secondes à démarrer. Si toutes
# les tentatives échouent, on déclenche le rollback (exigence 6).

log "Validation : health check sur http://localhost:${TEST_PORT}${HEALTH_PATH}"

health_ok=false
for attempt in $(seq 1 "$HEALTH_RETRIES"); do
    sleep "$HEALTH_DELAY"
    if curl --fail --silent --show-error "http://localhost:${TEST_PORT}${HEALTH_PATH}" > /dev/null 2>>"$LOG_FILE"; then
        health_ok=true
        break
    fi
    log "Tentative $attempt/$HEALTH_RETRIES : application pas encore disponible, nouvel essai..."
done

if [ "$health_ok" = false ]; then
    log "Le health check a échoué après $HEALTH_RETRIES tentatives."
    rollback
    # rollback() se termine par un exit 1, cette ligne n'est jamais atteinte
fi

log "OK : l'application répond correctement sur ${HEALTH_PATH}."

# --- 10. RÉCAPITULATIF -------------------------------------------------------

log "=== Déploiement terminé avec succès ==="
log "Application disponible sur : http://localhost:${TEST_PORT}"
log "Log complet : $LOG_FILE"

exit 0
