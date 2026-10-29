# Sauvegardes

- Le service `backup` (compose) fait un `pg_dump` compressé chaque jour à 02:00.
- Fichiers : `./backups/daily/*.sql.gz` (lien `./backups/last/` vers le dernier). Rétention : 5 jours, purge automatique.
- Les backups sont sur le même disque que la base : copiez `./backups` ailleurs régulièrement.
- Manuel : `make backup-now` · Liste : `make backup-list`
- Restauration : `make restore file=backups/daily/<fichier>.sql.gz` (écrase la base, confirmation demandée).
- `make migrate-docker` déclenche un backup avant `alembic upgrade head`.
- Testez régulièrement une restauration sur une base temporaire.
