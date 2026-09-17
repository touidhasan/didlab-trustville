# services

Server-side pieces, added in phase D4. v1 of the site is static and needs none of these.

- `api/` — small Node API for the app (history views, instructor progress page)
- `indexer/` — reads contract events from eth.didlab.org into the tenant's Postgres sidecar
- `oracle/` — posts signed weather values for the Insurer module; instructor trigger button

Secrets for these go in the cPanel tenant **Env** tab, never in this repository.
