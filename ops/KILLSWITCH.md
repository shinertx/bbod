# Emergency Kill-Switch Playbook

1. Stop all daemons and bots with `pm2 stop all` or your supervisor.
2. Disable the frontend or serve a maintenance page.
3. Set `NEXT_PUBLIC_ALERT` in `.env` to warn users and redeploy the frontend.
4. Notify users via social channels.
