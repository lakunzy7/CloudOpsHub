# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CloudOpsHub is an automated Docker-based infrastructure platform with GitOps and continuous delivery. The main application is **TheEpicBook**, an online bookstore (Node.js/Express) located in `theepicbook/`.

## Common Commands

All commands run from `theepicbook/`:

```bash
npm install          # Install dependencies
npm start            # Start server (port 8080)
npm test             # Runs linting (no unit tests exist)
npm run lint         # ESLint check
```

## Architecture

**TheEpicBook** follows MVC pattern:
- **server.js** - Express entry point, configures Handlebars templating, mounts routes, syncs Sequelize models then listens on PORT (default 8080)
- **models/** - Sequelize models (Book, Author, Cart, Checkout) auto-loaded by `models/index.js` which reads all `.js` files in the directory
- **routes/html-routes.js** - Page rendering routes (/, /cart, /gallery)
- **routes/cart-api-routes.js** - REST API for cart operations (exported as function taking `app`)
- **views/** - Handlebars templates with `layouts/main.handlebars` as default layout
- **public/** - Static assets (CSS, JS, images)
- **config/config.json** - Sequelize DB config per environment (development/test/production)
- **db/** - SQL seed files and CSVs for books/authors

Database: MySQL via Sequelize ORM. Production uses `JAWSDB_URL` env variable.

## Code Style

ESLint enforces: 2-space indent, double quotes, semicolons required, camelCase, strict equality (`===`), curly braces required. See `.eslintrc.json`.

## Infrastructure Context

The broader project (described in `Project.md`) involves Docker containerization, Terraform IaC, CI/CD pipelines, and ArgoCD/Flux GitOps across dev/staging/production environments. Travis CI is configured for linting.
