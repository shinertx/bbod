# Backup Daemon Guide

Run a secondary blob daemon pointing to backup RPC and beacon endpoints. Monitor both instances via the `/health` endpoint (port from `METRICS_PORT`). Switch traffic or restart if the primary fails.
