# PsyClinic API

A Rails 7.1 API-only backend for a clinical-psychology practice:
account approval, therapist discovery, calendar-based booking with
payment, document/avatar uploads, in-app + email notifications, an admin
dashboard, and scheduled appointment reminders.

> Auth is JWT (devise + devise-jwt). API-only, JSON everywhere.

---

## Stack

- Ruby 3.1, Rails 7.1, PostgreSQL
- Devise + devise-jwt (Bearer tokens), CanCanCan (authorization)
- Active Storage (local disk) for avatars & documents
- Action Mailer (logged in dev, `:test` in test, SMTP-via-ENV in prod)
- Docker Compose: `db`, `web`, and a `scheduler` service

## Roles & accounts

Three roles: `client`, `therapist`, `admin`.

Clients and therapists **self-register and start `pending`**; they
cannot log in until an admin approves them. Admins are created already
approved (seeds / promotion only — the role cannot be self-assigned via
signup).

Seeded accounts (password `Password123!`):

| Email                     | Role      | Status   |
|---------------------------|-----------|----------|
| admin@psyclinic.test      | admin     | approved |
| therapist@psyclinic.test  | therapist | approved |
| client@psyclinic.test     | client    | approved |

Seeds also create one approved slot ~36h out with a paid, booked
appointment so the dashboard and reminder task have realistic data.

---

## Running

```bash
docker compose up -d                 # db + web (:3000) + scheduler
curl -s http://localhost:3000/up     # green page = healthy
```

Tests:

```bash
docker compose run --rm -e RAILS_ENV=test web \
  sh -c "bundle exec rails db:prepare && bundle exec rspec"
```

---

## Auth

```bash
# Login -> JWT comes back in the Authorization response header
curl -i -X POST http://localhost:3000/api/v1/login \
  -H "Content-Type: application/json" \
  -d '{"user":{"email":"client@psyclinic.test","password":"Password123!"}}'

# Use it on subsequent calls
curl http://localhost:3000/api/v1/me -H "Authorization: Bearer <TOKEN>"
```

Pending/rejected users receive `401` on login with a reason.

---

## Endpoints

### Public (no auth)
- `GET  /api/v1/public/therapists` — approved, active therapists (the
  "read about therapists" welcome page)
- `GET  /api/v1/public/therapists/:id`

### Account
- `POST /api/v1/signup` — registers a `pending` client/therapist;
  triggers a "pending" email + in-app notification
- `POST /api/v1/login`, `DELETE /api/v1/logout`
- `GET  /api/v1/me`

### Current user files (Active Storage)
- `PUT/DELETE /api/v1/me/avatar` (multipart field `avatar`)
- `GET/POST   /api/v1/me/documents` (field `document` or `documents[]`)
- `DELETE     /api/v1/me/documents/:id`

### Client
- `GET  /api/v1/client/availability_slots` — all bookable approved
  slots; filters: `?therapist_profile_id=`, `?date=YYYY-MM-DD`,
  `?month=YYYY-MM` (calendar view)
- `POST /api/v1/client/appointments` — books a slot; returns the
  appointment (`pending_payment`) and a payment with `client_secret`
- `GET/DELETE /api/v1/client/appointments[/:id]`
- `GET  /api/v1/client/payments/:id`
- `POST /api/v1/client/payments/:id/confirm` — finalizes payment
  (`force_failure=true` exercises the failure path)

### Therapist
- `GET /api/v1/therapist/clients` — clients who booked them
- `GET /api/v1/therapist/appointments`
- `.../therapist/availability_slots` — manage own slots

### Admin
- `GET   /api/v1/admin/dashboard` — pending applications, counts,
  payment inflows, monthly calendar (`?month=YYYY-MM`)
- `GET   /api/v1/admin/applications` — pending registrations
- `PATCH /api/v1/admin/applications/:id/approve|reject`
- `.../admin/clients`, `.../admin/therapists` — list / remove

---

## Booking + payment flow

1. Client picks an approved slot -> `POST /client/appointments`.
2. Appointment is created `pending_payment` (this reserves the slot so
   it can't be double-booked) and a `Payment` + gateway intent is
   created. Response includes `client_secret`.
3. Client completes payment -> `POST /client/payments/:id/confirm`.
4. On success: appointment -> `booked`; the therapist gets an email +
   in-app notification. On failure: appointment -> `payment_failed`,
   which releases the slot for others.

### Payment gateway (Stripe-shaped, pluggable)

`PaymentGateways.current` returns the active gateway. Today it is
`PaymentGateways::Fake` (a simulated Stripe PaymentIntent, no network).
To go live with Stripe: implement `PaymentGateways::Stripe < Base`
(using `Stripe::PaymentIntent`) and point `PaymentGateways.current` at
it. Nothing else changes — controllers/services only talk to the `Base`
interface (`create_intent`, `confirm`).

---

## Appointment reminders

`SendAppointmentReminders` finds `booked` appointments starting within
2 days that have not been reminded, emails + notifies the therapist,
and records `reminder_sent_at` (idempotent — safe to run repeatedly).

Triggered by a rake task:

```bash
bundle exec rake appointments:send_reminders
```

The `scheduler` Docker service runs this hourly (a transparent shell
loop in its own container, isolated from the API — if it dies the API
is unaffected). To schedule elsewhere (host cron, k8s CronJob), run the
same rake task on your preferred interval.

Manual check:

```bash
docker compose run --rm web bundle exec rake appointments:send_reminders
# -> [appointments:send_reminders] reminded N appointment(s)
```

---

## Notifications & email

In-app: `Notification` records per user (application pending/approved/
rejected, appointment booked, appointment reminder).

Email: development logs the full email (no SMTP needed — see
`docker compose logs web`); test uses the `:test` adapter; production
reads SMTP settings from ENV. No third-party mail gems.

---

## Testing & verification notes

The suite covers approval, pairing-free booking, payments, uploads,
welcome page, dashboard, and reminder logic. The scheduler itself is
verified operationally (`docker compose logs scheduler`) rather than by
the suite, since its correctness is "does it run on schedule," not unit
behavior.
