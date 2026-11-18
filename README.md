# STUDY — Learn with direction

A responsive study and exam management platform for students and teachers. Built with React, TypeScript and Vite; GitHub Actions deploys it to GitHub Pages.

## Open the app

After the first successful GitHub Pages deployment:

- Student workspace: https://namankumar6280.github.io/study/?role=student
- Teacher workspace: https://namankumar6280.github.io/study/?role=teacher

These are role-specific demo entry links. In demo mode, role selection is only a preview and is not secure access control. For real teacher/student accounts, configure Supabase and grant teacher roles only through an administrator.

## Features

- Role-specific student and teacher workspaces
- Overview dashboard, assessment discovery and subject filters
- Timed multiple-choice exam runner with question navigation
- Demo scoring and progress history
- Teacher assessment builder and study-resource upload UI
- Student insights, profile settings and demo account switching
- Supabase Auth, Postgres and private Storage integration points
- Database schema with Row Level Security policies
- GitHub Actions build and GitHub Pages deployment

## Run locally

```bash
npm install
npm run dev
```

See [docs/SETUP.md](docs/SETUP.md) for Supabase setup and production hardening.

## Security status

This is an MVP, not a production-secure examination service. Demo data is stored in browser local storage. Correct answers must be delivered and graded server-side before real exams are used. Do not use demo mode for high-stakes assessments. Never put a Supabase service-role key in frontend environment variables.

## Stack

React 19 · TypeScript · Vite · Supabase JS · Lucide · GitHub Pages
