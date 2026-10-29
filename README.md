# Amzer API — API Feuilles de Temps

API FastAPI (SQLModel async, PostgreSQL 16, Alembic) livrée avec Docker Compose.

## Démarrage rapide

```bash
cp .env.example .env        # puis renseigner les valeurs (voir ci-dessous)
docker login ghcr.io -u <utilisateur>  # avec le token d'accès fourni, voir « Images Docker »
docker network create amzer-net   # une seule fois, voir « Réseau partagé »
docker compose up -d              # tire les images api, db (base déjà remplie) et backup
curl http://localhost:8000/health                 # {"status":"ok"}
```

Documentation interactive : `http://localhost:8000/docs` (désactivable avec `ENABLE_DOCS=false`).

## Configuration (`.env`)

| Variable | Rôle |
|---|---|
| `IMAGE_REGISTRY`, `IMAGE_TAG` | Dépôt des images dans le GitHub Container Registry (`ghcr.io/victor-mkw`) et tag (`latest` par défaut). Le compose en déduit `…/amzer-api`, `…/amzer-db` et `…/amzer-backup`. |
| `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` | Compte et base **figés dans l'image** `db` : reprendre les valeurs communiquées avec le token. Les modifier ne change pas la base. |
| `SECRET_KEY` | Signature des JWT. 32 caractères minimum. `python -c "import secrets; print(secrets.token_urlsafe(48))"` |
| `DATABASE_URL` | Utilisée hors Docker uniquement. Sous Compose, elle est reconstruite vers le service `db`. |
| `CORS_ORIGINS` | Liste JSON des sites web autorisés à appeler l'API depuis le navigateur, par exemple `["https://dash.exemple.fr"]`. |
| `ENABLE_DOCS` | `false` en production pour masquer `/docs`, `/redoc` et `/openapi.json`. |
| `DB_POOL_SIZE`, `DB_MAX_OVERFLOW`, `DB_POOL_TIMEOUT` | Pool de connexions **par worker**. |
| `WEB_CONCURRENCY` | Nombre de workers gunicorn (4 par défaut). Prévoir `WEB_CONCURRENCY × (DB_POOL_SIZE + DB_MAX_OVERFLOW)` connexions, sous `max_connections` de Postgres (100 par défaut). |
| `FORWARDED_ALLOW_IPS` | IP du reverse proxy de confiance, pour les en-têtes `X-Forwarded-*`. |
| `FINANCE_*` | Jeton et dérivation de clé du module finance (chiffrement de salary/charge). |

## Services

| Service | Rôle |
|---|---|
| `db` | PostgreSQL 16 depuis l'image `db` du registry (base déjà restaurée), données dans le volume `dbdata`, aucun port publié. |
| `backup` | Image `backup` du registry (copie de `prodrigestivill/postgres-backup-local:16`) : `pg_dump` quotidien dans `./backups`, rétention 5 jours. Voir [docs/BACKUP.md](docs/BACKUP.md). |
| `api` | Image `api` du registry (gunicorn + workers uvicorn), port 8000. `docker compose build api` la reconstruit depuis le code. |
| `migrate` | Tâche ponctuelle `alembic upgrade head` (profil `tools`). |

```bash
make up              # docker compose up -d
make down
make migrate		 # évolution du schéma de base de donnée
```


## Images Docker (GitHub Container Registry)

Trois images privées sont disponibles sur `ghcr.io/victor-mkw` : `amzer-api`, `amzer-db` et `amzer-backup`. Leur accès demande le token en lecture seule (`read:packages`) fourni par l'équipe. L'image `db` embarque une base PostgreSQL déjà restaurée (schéma et données) ; `api` ne contient aucun secret (le `.env` reste exclu). Le volume `dbdata` est initialisé depuis l'image au **premier** démarrage ; ensuite il garde ses propres données.

> L'image `db` contient des données de production (comptes, salaires/charges chiffrés) : ne la republiez pas et ne partagez pas le token.

### Récupérer et lancer les images

```bash
echo "$TOKEN" | docker login ghcr.io -u <utilisateur> --password-stdin
# .env : IMAGE_REGISTRY, IMAGE_TAG et POSTGRES_* tels que communiqués avec le token
docker compose pull
docker compose up -d
```

Pour repartir de l'image (perte des données du volume) : `docker compose down -v` puis `docker compose up -d`.


## Réseau partagé avec l'application Dash

L'API et l'application Dash tournent dans deux Compose séparés. Elles communiquent par un réseau Docker externe, `amzer-net`. Seul le service `api` y est rattaché ; `db` et `backup` restent sur le réseau privé du Compose et ne sont pas joignables depuis Dash.

**1. Créer le réseau, une seule fois :**

```bash
docker network create amzer-net
```

**2. Compose de l'API** (déjà en place dans `docker-compose.yml`) :

```yaml
services:
  api:
    networks:
      default:                  # à garder : sinon api perd l'accès à db
      amzer-net:
        aliases: [amzer-api]

networks:
  amzer-net:
    external: true
```

**3. Compose de Dash :**

```yaml
services:
  dash:
    environment:
      API_URL: http://amzer-api:8000/api/v1
    networks:
      default:
      amzer-net:

networks:
  amzer-net:
    external: true
```

**4. Vérifier :**

```bash
docker network inspect amzer-net --format '{{range .Containers}}{{.Name}} {{end}}'
docker compose exec dash python -c "import urllib.request as u; print(u.urlopen('http://amzer-api:8000/health').read())"
```

Le premier doit lister l'API (et Dash), pas la base. Le second doit afficher `{"status":"ok"}`.

À savoir :

- Le port interne est toujours `8000`, quel que soit le port publié sur l'hôte.
- L'alias `amzer-api` évite un conflit si le Compose de Dash a déjà un service nommé `api`.
- Les deux Compose doivent déclarer le réseau en `external: true`. Sinon chacun crée son propre réseau et ils ne se voient pas.
- Cette URL interne ne fonctionne que pour des appels **côté serveur** (callbacks Python de Dash). Si le navigateur de l'utilisateur appelle l'API directement, il faut l'URL publique et ajouter l'origine de Dash à `CORS_ORIGINS`.
- Si l'API est publiée via le reverse proxy de l'IT, le port `8000:8000` peut être retiré ou limité à `127.0.0.1`, à condition que le proxy joigne l'API par un autre chemin.

### URL de l'API selon l'emplacement de Dash

| Où tourne Dash | URL de base |
|---|---|
| Hôte, hors Docker | `http://localhost:8000/api/v1` |
| Conteneur sur `amzer-net` | `http://amzer-api:8000/api/v1` |
| Production, derrière le proxy | URL publique HTTPS fournie par l'IT
## Évolution du schéma

Modifier les modèles, générer la migration en local (`make migrate msg="description"`), la **commiter**, puis sur le serveur :

```bash
make migrate-docker     # backup automatique, puis alembic upgrade head
```

Les données sont conservées. Les migrations destructrices (suppression de colonne, changement de type) demandent une vérification manuelle.

## Sauvegardes

Voir [docs/BACKUP.md](docs/BACKUP.md).
