# Deploy and Host Tracktor on Railway

Tracktor is a logbook for the vehicles you own. Record every fuel fill-up, service, repair,
insurance renewal and registration date, and it works out your running costs, fuel economy and
mileage over time. It is the kind of record most people keep badly in a glovebox folder or not at
all. This is a community-maintained template; it is not affiliated with the Tracktor project.

## About Hosting Tracktor

Tracktor is straightforward to host: one Node service, one SQLite database, one directory holding
the database, uploaded documents and logs. There is no companion database and no queue, so a
deployment is a single service with a single persistent volume.

The part that needs care is who can get in. Tracktor has a real login with hashed passwords and
session cookies, but its registration endpoint is exempt from the session check, and that exemption
does not expire when the first account is created. It keeps accepting new accounts for the life of
the instance. Accounts are also not separated from each other, so any account can see every vehicle,
including VIN and licence plate. On a home network that is a small thing. On a public address it
means a stranger can enrol themselves and read your records. This template creates your account
before the service is reachable and refuses the registration route afterwards, so the instance is
yours from the first second it exists.

## Why Deploy Tracktor on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your
infrastructure so you don't have to deal with configuration, while allowing you to vertically and
horizontally scale it.

By deploying Tracktor on Railway, you are one step closer to supporting a complete full-stack
application with minimal burden. Host your servers, databases, AI agents, and more on Railway.

Concretely, this template attaches the volume, generates your password and the application secret,
creates your account, pins the listening port to the generated domain, marks session cookies secure,
restricts browser origins to your own domain, and closes registration, with nothing to fill in.

## Common Use Cases

- Log a fill-up from your phone at the pump, and see real fuel economy instead of the dashboard's
  guess.
- Keep every service and repair against the right car, so the history is ready when you sell it.
- Get reminders before insurance, registration or inspection dates lapse.
- Track what a vehicle actually costs per mile over years rather than per visit.

## Dependencies for Tracktor Hosting

- A persistent volume for the SQLite database, uploaded documents and logs.
- Nothing else. No external database, cache or queue.

### Deployment Dependencies

- Tracktor upstream project and documentation: https://github.com/javedh-dev/tracktor
- Tracktor environment reference: https://github.com/javedh-dev/tracktor/blob/main/docs/environment.md
- Caddy, used as the proxy that closes registration: https://caddyserver.com
- Template repository, wrapper image and tests: https://github.com/youssefsiam38/tracktor-railway
- Published image: `ghcr.io/youssefsiam38/tracktor-railway`
- Tracktor is MIT licensed and Caddy is Apache-2.0; both are permissive.

### Implementation Details

The wrapper adds no application code. It validates the configuration, refuses the settings that
would undo the protections, starts the application on loopback, waits for it to report healthy,
creates the owner account through the application's own endpoint, and only then opens the public
port with the registration route closed. Creating the account is idempotent, so changing your
password in the app is never undone by a redeploy.
