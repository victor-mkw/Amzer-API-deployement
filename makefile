# Commandes d'exploitation. À lancer depuis ce dossier (docker-compose.yml et .env à côté).

up:
	docker compose up -d

down:
	docker compose down

# Sauvegarde, puis alembic upgrade head
migrate-docker: backup-now
	docker compose --profile tools run --rm migrate

backup-now:
	docker compose exec backup /backup.sh

backup-list:
	ls -lh backups/last backups/daily

# usage: make restore file=backups/daily/<fichier>.sql.gz
restore:
	@test -n "$(file)" || (echo "usage: make restore file=<dump.sql.gz>"; exit 1)
	@read -p "Écraser la base actuelle avec $(file) ? [y/N] " a; [ "$$a" = "y" ]
	docker compose exec -T db sh -c 'psql -U $$POSTGRES_USER -d $$POSTGRES_DB -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"'
	gunzip -c $(file) | docker compose exec -T db sh -c 'psql -U $$POSTGRES_USER -d $$POSTGRES_DB'
