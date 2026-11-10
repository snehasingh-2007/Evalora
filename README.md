# Evalora — Faculty Feedback & Course Evaluation Portal

A redesigned HTML/CSS/JavaScript portal with a Supabase-backed data layer. It starts with **no demo accounts, no sample courses, no fabricated feedback, and no seeded analytics**. Dashboards and metrics are calculated from the records in your own database.

## Technology
- HTML5, CSS3, vanilla JavaScript modules
- Supabase Auth for sign-in and session management
- Supabase Postgres for profiles, courses, enrollments, feedback, announcements, settings, and audit records
- PostgreSQL Row Level Security (RLS) policies for role-based data access

## Setup before using the website

### 1. Create a Supabase project
Create a project at https://supabase.com/ and wait until its database is ready.

### 2. Create the tables and security policies
Open **SQL Editor** in Supabase, create a query, paste all of `schema.sql`, and run it. This creates tables and RLS policies, plus one portal-settings row for configuration. It does not create demo students, faculty, courses, or feedback.

### 3. Configure the front end
Open `config.js` and replace the placeholders with the project's **Project URL** and **publishable/anon key** from Supabase project API settings:

```js
window.EVALORA_CONFIG = {
  SUPABASE_URL: "https://YOUR-PROJECT.supabase.co",
  SUPABASE_ANON_KEY: "YOUR_SUPABASE_PUBLISHABLE_OR_ANON_KEY"
};
```

Only the publishable/anon key belongs in browser code. **Never place a `service_role` key in `config.js`, HTML, or JavaScript.**

### 4. Serve the files over HTTP
Do not rely on opening `index.html` as a `file://` URL. From this folder, run a local static server, for example:

```bash
python -m http.server 5500
```

Then open http://localhost:5500 in your browser. VS Code Live Server is also fine. Deploy the static files to a static host for remote access.

### 5. Create and promote the first administrator (one-time bootstrap)
In Supabase, open **Authentication → Users → Add user** and create the institution's first trusted administrator account. Enable email/password sign-in in Supabase Auth if it is not already enabled. Find that user's UUID in Authentication → Users, then run the SQL below with the actual UUID.

```sql
update public.profiles
set role = 'admin', full_name = 'Portal Administrator'
where id = 'REPLACE-WITH-THE-AUTH-USER-UUID';
```

This one-time bootstrap is necessary because no account is automatically granted admin access.

### 6. Deploy secure account provisioning
The **Create account** control uses a server-side Supabase Edge Function. Deploy it from the project folder with the Supabase CLI after linking the project:

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase functions deploy admin-create-user
```

The function uses Supabase's server-side environment secrets, verifies the caller's active admin role, and never exposes the service-role key to the browser. If you do not deploy this function, account creation from the portal will not work; existing Auth accounts can still sign in and admins can manage their profiles.

### 7. Create accounts and manage real data
After signing in as the initial administrator, create student and faculty accounts through **People & access → Create account**. Use a strong temporary password of at least 12 characters and share it securely.

### 8. Add actual institutional records
1. Sign in with the administrator account.
2. Open **Portal management → Add course** and add actual courses, departments, academic terms, and faculty assignments.
3. Open **People & access** to check profile roles and active status.
4. Use **Portal management → Manage enrollments** to assign students to courses.
5. Open the course's feedback window when it is ready, and publish the course.
6. Use **Portal settings** to configure institution name, welcome text, feedback guidance, and anonymous-display preference.


## Role capabilities
- **Student:** sees published courses in which their account is enrolled; can submit one evaluation per course while the feedback window is open; can see their own submission history.
- **Faculty:** sees courses assigned to their profile and feedback associated with those courses; student identity is not rendered in faculty feedback views.
- **Administrator:** manages course records, publication and feedback windows, announcements, profiles/roles/status, portal settings, exports, and audit activity.

## Data and privacy notes
- No fictional/sample records are inserted. Empty states are shown until real records exist.
- Feedback submission requires an enrollment record and an open feedback window. The database also prevents duplicate feedback for the same student/course pair.
- Anonymous display is not the same as fully anonymous storage: the database retains the student ID to enforce one submission per course. Database administrators can access underlying records. Confirm your institution's privacy requirements before collecting sensitive feedback.
- RLS policies are the security boundary; front-end navigation is not. Review policies with your institution's IT/security team before production use.
- Account creation is handled by the protected `admin-create-user` Edge Function. Account deletion is intentionally not included in the UI; disable access first and handle account deletion through a trusted administrative process.
- This package is a static frontend plus database schema, not a complete managed hosting service. Set up HTTPS, backups, appropriate retention, monitoring, and institutional approval before real-world deployment.

## Files
- `index.html` — sign-in page and application shell
- `styles.css` — responsive visual system and portal components
- `app.js` — authentication, database reads/writes, role-specific screens, admin workflows, analytics and CSV export
- `config.js` — Supabase public client configuration (fill in your own project values)
- `schema.sql` — database tables, RLS policies, profile trigger, settings row
- `supabase/functions/admin-create-user/index.ts` — secure server-side account provisioning
