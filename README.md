# PsyClinic API

Backend for a clinical-psychologist practice management system.
Rails 7.1.3.4 (API-only) · Ruby 3.1.0 · PostgreSQL · Devise + devise-jwt · CanCanCan.

## Roles

- **Client** – books sessions with the therapist they are paired to.
- **Therapist** – proposes availability, sees their paired clients, manages their appointments.
- **Admin (Head-Therapist)** – manages users, pairs clients↔therapists, approves availability, manages specializations.

Admins cannot be created via public signup (guarded in `User`). The first admin
comes from `db/seeds.rb`.

## Run locally with Docker (recommended)

Prerequisites: Docker + Docker Compose.

```bash
cd psyclinic
docker compose up --build
```

This will:
1. start PostgreSQL 16,
2. wait for it to be healthy,
3. create the DB, run all migrations (`rails db:prepare`),
4. seed an admin/therapist/client (idempotent),
5. boot Puma on http://localhost:3000

Health check: `curl http://localhost:3000/up` → `200`

The app inside the container still listens on port 3000; only the host
port differs. To change which host port you use, edit the left side of
the `ports` mapping in `docker-compose.yml` (`HOST:3000`).

Seeded accounts (password `Password123!` for all):
- `admin@psyclinic.test`
- `therapist@psyclinic.test`
- `client@psyclinic.test`

Reset everything:

```bash
docker compose down -v && docker compose up --build
```

## Run locally without Docker

Requires Ruby 3.1.0, PostgreSQL running locally.

```bash
bundle install
export DATABASE_USERNAME=postgres DATABASE_PASSWORD=postgres
export DEVISE_JWT_SECRET_KEY=$(openssl rand -hex 32)
export SECRET_KEY_BASE=$(openssl rand -hex 64)
bin/rails db:prepare
bin/rails db:seed
bin/rails s
```

## Tests

```bash
docker compose run --rm web bundle exec rspec
# or locally:
RAILS_ENV=test bundle exec rspec
```

## Auth

1. `POST /api/v1/login` with `{ "user": { "email", "password" } }`.
2. Read the `Authorization: Bearer <jwt>` response header.
3. Send that header on every subsequent request.
4. `DELETE /api/v1/logout` revokes the token (denylist).

## API reference

### Public
| Method | Path | Body |
|---|---|---|
| POST | `/api/v1/signup` | `user: {email,password,password_confirmation,first_name,last_name,phone,role}` (role: client/therapist) |
| POST | `/api/v1/login` | `user: {email,password}` |
| DELETE | `/api/v1/logout` | — |
| GET | `/api/v1/me` | — (current user) |

### Admin (`/api/v1/admin`)
| Method | Path | Purpose |
|---|---|---|
| GET | `/clients` | list registered clients |
| GET/DELETE | `/clients/:id` | view / remove a client |
| GET | `/therapists` | list therapists |
| POST | `/therapists` | add a therapist user (`therapist: {email,password,...,bio,license_number}`) |
| DELETE | `/therapists/:id` | remove a therapist |
| GET/POST/DELETE | `/specializations` | manage specializations |
| POST/DELETE | `/therapist_specializations` | attach/detach a specialization |
| GET/POST/DELETE | `/pairings` | pair (`client_profile_id`,`therapist_profile_id`) / unpair |
| GET | `/availability_slots` | all slots (filter `?status=`) |
| PATCH | `/availability_slots/:id/approve` | approve a proposed slot |
| PATCH | `/availability_slots/:id/reject` | reject a slot |

### Therapist (`/api/v1/therapist`)
| Method | Path | Purpose |
|---|---|---|
| GET | `/clients` | clients paired to me |
| GET/POST/PATCH/DELETE | `/availability_slots` | manage my availability |
| GET/PATCH | `/appointments` | my appointments (PATCH `status`) |

### Client (`/api/v1/client`)
| Method | Path | Purpose |
|---|---|---|
| GET | `/availability_slots` | bookable slots for my paired therapist |
| GET | `/appointments` | my appointments |
| POST | `/appointments` | book (`availability_slot_id`, `reason`) |
| DELETE | `/appointments/:id` | cancel my booking |

## Architecture notes

- **Profiles split** from the auth `users` table so client/therapist data
  scale independently.
- **AvailabilitySlot** is a first-class record; booking is a locked
  transaction (`SELECT … FOR UPDATE`) backed by a partial unique index
  (`idx_one_active_appointment_per_slot`) so concurrent requests cannot
  double-book.
- **Authorization** is centralized in `app/models/ability.rb`. Every
  controller calls `authorize!`.
- **Stateless JWT** with a DB denylist for logout — horizontally scalable.

## Known limitations (MVP)

- `Gemfile.lock` is generated inside the image rather than committed, so
  builds are not byte-reproducible. Commit a lockfile for production.
- No pagination yet on list endpoints.
- Email delivery is not configured (password reset will not send mail).
- This codebase was statically verified (syntax, route↔controller wiring,
  authorization rules) but not booted in this environment; run the test
  suite after `docker compose up` to confirm runtime behavior.
