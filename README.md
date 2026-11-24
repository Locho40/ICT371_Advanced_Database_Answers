# ICT371 Advanced Database — Complete SQL Answers

Contains PostgreSQL solutions for Questions 1–10 from `Last one ICT371.pdf`.

## Files
- `Q1_pharmacy.sql` through `Q10_scholarship.sql`: one independent script per question.
- Run each script in PostgreSQL using pgAdmin Query Tool or `psql`.
- Each script creates its own schema (`q1_pharmacy`, etc.) to prevent name collisions.

## Scheduled jobs
The scheduled-job sections use the PostgreSQL `pg_cron` extension. Install/configure `pg_cron` on the PostgreSQL server first, then run the relevant scheduling statements. If `pg_cron` is unavailable, the procedures can still be run manually with the shown `CALL` statements.

## Important
Run scripts in a test database first. The scripts use sample data and `DROP SCHEMA ... CASCADE` so rerunning a script resets only that question's schema.
