# STUDY — Learn with direction

A responsive student and teacher study workspace published directly from this repository with GitHub Pages.

## App links

After GitHub Pages is enabled and the deployment workflow succeeds:

- Student workspace: https://namankumar6280.github.io/study/?role=student
- Teacher workspace: https://namankumar6280.github.io/study/?role=teacher

Both links open the same site with a different demo workspace selected.

## Included features

- Student dashboard and assessment discovery
- Subject filtering and timed multiple-choice assessments
- Question navigation, automatic scoring and progress history
- Teacher dashboard, assessment creation and publishing
- Study library with local resource listing
- Student insights and profile settings
- Responsive mobile and desktop layout
- Browser-local demo data storage
- GitHub Actions deployment to GitHub Pages

## Important limitations

This published build is a front-end demo. Data is stored in the current browser and is not shared between students, teachers or devices. The teacher link is a demo preview, not secure teacher authentication. Do not use it for real confidential assessments or high-stakes exams. A real multi-user platform needs a configured backend (for example Supabase), server-side answer grading, administrator-controlled teacher roles, and database security policies.

## Repository

The website source is in [site/index.html](site/index.html). Deployment is configured in [.github/workflows/deploy.yml](.github/workflows/deploy.yml).
